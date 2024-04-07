#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import ssl
import subprocess
from copy import deepcopy
from functools import partial
from glob import glob
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

# UID for the folder under which our dashboards will be setup
DEFAULT_FOLDER_UID = '70E5EE84-1217-4021-A89E-1E3DE0566D93'


def grafana_request(endpoint, token, path, data=None, no_tls_verify=False):
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    method = 'GET' if data is None else 'POST'
    req = Request(f'{endpoint}/api{path}', headers=headers, method=method)

    if not isinstance(data, bytes):
        data = json.dumps(data).encode()

    ctx = None

    if no_tls_verify:
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE

    with urlopen(req, data, context=ctx) as resp:
        return json.load(resp)


def ensure_folder(name, uid, api):
    try:
        return api(f'/folders/{uid}')
    except HTTPError as e:
        if e.code == 404:
            # We got a 404 in
            folder = {'uid': uid, 'title': name}
            return api('/folders', folder)
        else:
            raise


def build_dashboard(dashboard_path, api):
    datasources = api("/datasources")
    datasources_names = [ds["name"] for ds in datasources]

    # We pass the list of all datasources because the global dashboards
    # use this information to show info about all datasources in the same panel
    return json.loads(
        subprocess.check_output(
            [
                "jsonnet",
                "-J",
                "vendor",
                dashboard_path,
                "--tla-code",
                f"datasources={datasources_names}",
            ]
        ).decode()
    )


def deploy_dashboard(dashboard_path, folder_uid, api):
    db = build_dashboard(dashboard_path, api)
    # without this modification, deploying to a second folder deletes deployed
    # dashboards in another folder, likely due to generated dashboard UID is the
    # same as an already existing dashboard UID. They are probably generated
    # based on some hash that didn't get new input when deployed to the second
    # folder compared to initially deployed to the first folder.
    db['uid'] = hashlib.sha256((dashboard_path + folder_uid).encode()).hexdigest()[:16]

    if not db:
        return

    db = populate_template_variables(api, db)

    data = {'dashboard': db, 'folderUid': folder_uid, 'overwrite': True}
    api('/dashboards/db', data)


def get_label_values(api, ds_id, template_query):
    """
    Return response to a `label_values` template query

    `label_values` isn't actually a prometheus thing - it is an API call that
    grafana makes. This function tries to mimic that. Useful for populating variables
    in a dashboard
    """
    # re.DOTALL allows the query to be multi-line
    match = re.match(
        r'label_values\((?P<query>.*),\s*(?P<label>.*)\)', template_query, re.DOTALL
    )
    query = match.group('query')
    label = match.group('label')
    query = {'match[]': query}
    # Send a request to the backing prometheus datastore
    proxy_url = f'/datasources/proxy/{ds_id}/api/v1/series?{urlencode(query)}'

    metrics = api(proxy_url)['data']
    return sorted({m[label] for m in metrics})


def populate_template_variables(api, db):
    """
    Populate options for template variables.

    For list of hubs and similar, users should be able to select a hub from
    a dropdown list. This is not automatically populated by grafana if you are
    using the API (https://community.grafana.com/t/template-update-variable-api/1882/4)
    so we do it here.
    """
    # We're going to make modifications to db, so let's make a copy
    db = deepcopy(db)

    for var in db.get('templating', {}).get('list', []):
        datasources = api("/datasources")
        if var["type"] == "datasource":
            var["options"] = [
                {"text": ds["name"], "value": ds["name"]} for ds in datasources
            ]

            # default selection: first datasource in list
            if datasources and not var.get("current"):
                var["current"] = {
                    "selected": True,
                    "tags": [],
                    "text": datasources[0]["name"],
                    "value": datasources[0]["name"],
                }
                var["options"][0]["selected"] = True
        elif var['type'] == 'query':
            template_query = var['query']

            # This requires our token to have admin permissions
            # Default to the first datasource
            prom_id = datasources[0]["id"]

            labels = get_label_values(api, prom_id, template_query)
            var["options"] = [{"text": label, "value": label} for label in labels]
            if labels and not var.get("current"):
                # default selection: all current values
                # logical alternative: pick just the first
                var["current"] = {
                    "selected": True,
                    "tags": [],
                    "text": labels[0],
                    "value": labels[0],
                }
                var["options"][0]["selected"] = True

    return db


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('grafana_url', help='Grafana endpoint to deploy dashboards to')
    parser.add_argument(
        '--dashboards-dir',
        default="dashboards",
        help='Directory of jsonnet dashboards to deploy',
    )
    parser.add_argument(
        '--folder-name',
        default='JupyterHub Default Dashboards',
        help='Name of Folder to deploy to',
    )
    parser.add_argument(
        '--folder-uid',
        default=DEFAULT_FOLDER_UID,
        help='UID of grafana folder to deploy to',
    )
    parser.add_argument(
        '--no-tls-verify',
        action='store_true',
        default=False,
        help='Whether or not to skip TLS certificate validation',
    )

    args = parser.parse_args()

    grafana_token = os.environ['GRAFANA_TOKEN']

    api = partial(
        grafana_request,
        args.grafana_url,
        grafana_token,
        no_tls_verify=args.no_tls_verify,
    )
    ensure_folder(args.folder_name, args.folder_uid, api)

    for dashboard in glob(f'{args.dashboards_dir}/*.jsonnet'):
        deploy_dashboard(dashboard, args.folder_uid, api)
        print(f'Deployed {dashboard}')


if __name__ == '__main__':
    main()
