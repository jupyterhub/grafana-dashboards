#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import shutil
import ssl
import subprocess
from functools import partial
from glob import glob
from urllib.error import HTTPError
from urllib.request import Request, urlopen

# UID for the folder under which our dashboards will be setup
DEFAULT_FOLDER_UID = '70E5EE84-1217-4021-A89E-1E3DE0566D93'


def grafana_request(endpoint, token, path, data=None, method=None, no_tls_verify=False):
    headers = {'Authorization': f'Bearer {token}', 'Content-Type': 'application/json'}
    method = method or ('GET' if data is None else 'POST')
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


def ensure_folder(title, uid, api):
    """
    Checks for a folder based on its UID and creates one if needed or updates
    the title if needed.
    """
    try:
        # api ref: https://grafana.com/docs/grafana/latest/developers/http_api/folder/#get-folder-by-uid
        folder = api(f'/folders/{uid}')
        if folder["title"] != title:
            # api ref: https://grafana.com/docs/grafana/latest/developers/http_api/folder/#update-folder
            api(
                f'/folders/{uid}',
                {'title': title, 'version': folder["version"]},
                method='PUT',
            )
    except HTTPError as e:
        if e.code == 404:
            # api ref: https://grafana.com/docs/grafana/latest/developers/http_api/folder/#create-folder
            api('/folders', {'uid': uid, 'title': title})
        else:
            raise


def build_dashboard(dashboard_path, api):
    """
    Returns JSON representing a Grafana dashboard by rendering an individual
    `.jsonnet` dashboard template with `jsonnet`.
    """
    dashboard = json.loads(
        subprocess.check_output(
            [
                "jsonnet",
                "-J",
                "vendor",
                dashboard_path,
            ],
            text=True,
        )
    )
    if not dashboard:
        raise ValueError(f"jsonnet render of {dashboard_path} led to an empty object")
    return dashboard


def deploy_dashboard(dashboard_path, folder_uid, api):
    """
    Creates a new dashboard or updates an existing dashboard.
    """
    db = build_dashboard(dashboard_path, api)

    # without this modification, deploying to a second folder deletes deployed
    # dashboards in another folder, likely due to generated dashboard UID is the
    # same as an already existing dashboard UID. They are probably generated
    # based on some hash that didn't get new input when deployed to the second
    # folder compared to initially deployed to the first folder.
    db['uid'] = hashlib.sha256((dashboard_path + folder_uid).encode()).hexdigest()[:16]

    # api ref: https://grafana.com/docs/grafana/latest/developers/http_api/dashboard/#create--update-dashboard
    data = {'dashboard': db, 'folderUid': folder_uid, 'overwrite': True}
    api('/dashboards/db', data)


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

    # ensure GRAFANA_TOKEN
    grafana_token = os.environ.get("GRAFANA_TOKEN")
    if not grafana_token:
        raise ValueError(
            "The environment variable GRAFANA_TOKEN needs to be set in order to deploying dashboards to a Grafana deployment."
        )

    # ensure jsonnet
    if not shutil.which("jsonnet"):
        raise ValueError(
            "No jsonnet binary was found on path! "
            "Install go-jsonnet via https://github.com/google/go-jsonnet/releases."
        )

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
