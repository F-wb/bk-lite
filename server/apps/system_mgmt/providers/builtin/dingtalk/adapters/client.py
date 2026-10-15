"""本包厂商请求层：钉钉 OAuth2.0 HTTP。能力模块不要再抄一份 requests。"""

import requests

DINGTALK_TIMEOUT = 10
DINGTALK_AUTHORIZE_URL = "https://login.dingtalk.com/oauth2/auth"
DINGTALK_USER_ACCESS_TOKEN_URL = "https://api.dingtalk.com/v1.0/oauth2/userAccessToken"
DINGTALK_USER_INFO_URL = "https://api.dingtalk.com/v1.0/contact/users/me"


def _get_config_value(config: dict, key: str, default: str):
    return (config or {}).get(key) or default


def _post_json(url, json_body, *, headers=None):
    """本包 HTTP POST JSON；能力模块不要各自再抄 requests。"""
    return requests.post(url, json=json_body, headers=headers or {}, timeout=DINGTALK_TIMEOUT)


def _get(url, *, headers=None, params=None):
    """本包 HTTP GET；能力模块不要各自再抄 requests。"""
    return requests.get(url, headers=headers or {}, params=params, timeout=DINGTALK_TIMEOUT)
