#!/usr/bin/env python3
import json
import argparse
import os
from glob import glob
from functools import partial
import subprocess
from urllib.request import urlopen, Request
from urllib.parse import urlencode
from urllib.error import HTTPError
from copy import deepcopy
import re

# UID for the folder under which our dashboards will be setup
DEFAULT_FOLDER_UID = '70E5EE84-1217-4021-A89E-1E3DE0566D93'

def grafana_request(endpoint, token, path, data=None):
    headers = {
        'Authorization': f'Bearer {token}',
        'Content-Type': 'application/json'
    }
    method = 'GET' if data is None else 'POST'
    req = Request(f'{endpoint}/api{path}', headers=headers, method=method)
    if not isinstance(data, bytes):
        data = json.dumps(data).encode()
    with urlopen(req, data) as resp:
        return json.load(resp)


def ensure_folder(name, uid, api):
    try:
        return api(f'/folders/{uid}')
    except HTTPError as e:
        if e.code == 404:
            # We got a 404 in
            folder = {
                'uid': uid,
                'title': name
            }
            return api('/folders', folder)
        else:
            raise



def build_dashboard(dashboard_path):
    return json.loads(subprocess.check_output([
        'jsonnet', '-J', 'vendor',
        dashboard_path
    ]).decode())


def layout_dashboard(dashboard):
    """
    Automatically layout panels.

    - Default to 12x10 panels
    - Reset x axes when we encounter a row
    - Assume 24 unit width

    Grafana's autolayout is not available in the API, so we
    have to do thos.
    """
    # Make a copy, since we're going to modify this dict
    dashboard = deepcopy(dashboard)
    cur_x = 0
    cur_y = 0
    for panel in dashboard['panels']:
        pos = panel['gridPos']
        pos['h'] = pos.get('h', 10)
        pos['w'] = pos.get('w', 12)
        pos['x'] = cur_x
        pos['y'] = cur_y

        cur_y += pos['h']
        if panel['type'] == 'row':
            cur_x = 0
        else:
            cur_x = (cur_x + pos['w']) % 24

    return dashboard

def deploy_dashboard(dashboard_path, folder_uid, api):
    db = build_dashboard(dashboard_path)
    db = layout_dashboard(db)
    db = populate_template_variables(api, db)

    data = {
        'dashboard': db,
        'folderId': folder_uid,
        'overwrite': True
    }
    api('/dashboards/db', data)


def get_label_values(api, ds_id, template_query):
    """
    Return response to a `label_values` template query

    `label_values` isn't actually a prometheus thing - it is an API call that
    grafana makes. This function tries to mimic that. Useful for populating variables
    in a dashboard
    """
    # re.DOTALL allows the query to be multi-line
    match = re.match(r'label_values\((?P<query>.*),\s*(?P<label>.*)\)', template_query, re.DOTALL)
    query = match.group('query')
    label = match.group('label')
    query = {'match[]': query}
    # Send a request to the backing prometheus datastore
    proxy_url = f'/datasources/proxy/{ds_id}/api/v1/series?{urlencode(query)}'

    metrics = api(proxy_url)['data']
    return sorted(set(m[label] for m in metrics))


def populate_template_variables(api, db):
    """
    Populate options for template variables.

    For list of hubs and similar, users should be able to select a hub from
    a dropdown list. This is not auto populated by grafana if you are
    using the API (https://community.grafana.com/t/template-update-variable-api/1882/4)
    so we do it here.
    """
    # We gonna make modifications to db, so let's make a copy
    db = deepcopy(db)

    for var in db.get('templating', {}).get('list', []):
        if var['type'] != 'query':
            # We don't support populating datasource templates
            continue
        template_query = var['query']

        # This requires our token to have admin permissions
        prom_id = api(f'/datasources/id/{var["datasource"]}')['id']

        labels = get_label_values(api, prom_id, template_query)
        var["options"] = [{"text": l, "value": l} for l in labels]
        if len(labels) == 1 and not var.get("current"):
            # default selection: all current values
            # logical alternative: pick just the first
            var["current"] = {
                "selected": True,
                "tags": [],
                "text": labels[0],
                "value": labels[:1],
            }
            var["options"][0]["selected"] = True

    return db

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('dashboards_dir', help='Directory of jsonnet dashboards to deploy')
    parser.add_argument('grafana_url', help='Grafana endpoint to deploy dashboards to')
    parser.add_argument('--folder-name', default='JupyterHub Default Dashboards', help='Name of Folder to deploy to')
    parser.add_argument('--folder-uid', default=DEFAULT_FOLDER_UID, help='UID of grafana folder to deploy to')

    args = parser.parse_args()

    grafana_token = os.environ['GRAFANA_TOKEN']

    api = partial(grafana_request, args.grafana_url, grafana_token)
    folder = ensure_folder(args.folder_name, args.folder_uid, api)

    for dashboard in glob(f'{args.dashboards_dir}/*.jsonnet'):
        deploy_dashboard(dashboard, folder['id'], api)

if __name__ == '__main__':
    main()
