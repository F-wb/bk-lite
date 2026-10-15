from urllib.parse import urlencode

import requests

from apps.system_mgmt.providers.log import logger
from apps.system_mgmt.providers.base import BaseLoginAuthAdapter
from apps.system_mgmt.providers.runtime import CapabilityExecutionResult

from .client import (
    DINGTALK_AUTHORIZE_URL,
    DINGTALK_TIMEOUT,
    DINGTALK_USER_ACCESS_TOKEN_URL,
    DINGTALK_USER_INFO_URL,
    _get,
    _get_config_value,
    _post_json,
)


class DingtalkLoginAuthAdapter(BaseLoginAuthAdapter):
    capability_key = "login_auth"

    @classmethod
    def test_connection(cls, config: dict, provider_key: str, capability_key: str, **kwargs):
        app_key = (config or {}).get("app_key", "")
        app_secret = (config or {}).get("app_secret", "")
        if not app_key or not app_secret:
            return CapabilityExecutionResult.failed_result(
                "DingTalk app_key or app_secret is missing",
                code="provider.invalid_config",
                field="app_key" if not app_key else "app_secret",
            )
        return CapabilityExecutionResult.success_result("DingTalk login capability is ready")

    @classmethod
    def build_login_url(cls, config: dict, provider_key: str, capability_key: str, **kwargs):
        app_key = (config or {}).get("app_key", "")
        redirect_uri = kwargs.get("redirect_uri", "")
        state = kwargs.get("state", "")
        if not app_key or not redirect_uri:
            return CapabilityExecutionResult.failed_result(
                "DingTalk login redirect configuration is incomplete",
                code="provider.invalid_config",
                field="app_key" if not app_key else "redirect_uri",
            )

        authorize_url = _get_config_value(config, "login_auth_authorize_url", DINGTALK_AUTHORIZE_URL)
        corp_id = (config or {}).get("corp_id", "").strip()

        # 钉钉新版统一身份认证（login.dingtalk.com/oauth2/auth）要求参数名 client_id
        # 个人扫码登录场景不传 corpId；企业内部应用场景传实际企业 corpId（形如 dingxxxx）
        query_params = {
            "client_id": app_key,
            "response_type": "code",
            "scope": "openid",
            "redirect_uri": redirect_uri,
            "state": state,
            "prompt": "consent",
        }
        if corp_id:
            query_params["corpId"] = corp_id
        query = urlencode(query_params)
        return CapabilityExecutionResult.success_result(
            "DingTalk login URL generated",
            payload={"authorize_url": f"{authorize_url}?{query}"},
        )

    @classmethod
    def authenticate(cls, config: dict, provider_key: str, capability_key: str, **kwargs):
        auth_code = kwargs.get("auth_code", "")
        app_key = (config or {}).get("app_key", "")
        app_secret = (config or {}).get("app_secret", "")
        if not auth_code:
            return CapabilityExecutionResult.failed_result(
                "DingTalk login request is missing required parameters",
                code="provider.invalid_config",
                field="auth_code",
            )
        if not app_key or not app_secret:
            return CapabilityExecutionResult.failed_result(
                "DingTalk app_key or app_secret is missing",
                code="provider.invalid_config",
                field="app_key" if not app_key else "app_secret",
            )

        # Step 1: code 换 userAccessToken
        token_url = _get_config_value(config, "login_auth_access_token_url", DINGTALK_USER_ACCESS_TOKEN_URL)
        try:
            token_response = _post_json(
                token_url,
                {
                    "clientId": app_key,
                    "clientSecret": app_secret,
                    "code": auth_code,
                    "grantType": "authorization_code",
                },
            )
        except requests.Timeout:
            return CapabilityExecutionResult.failed_result(
                "DingTalk login request timed out", code="provider.timeout", retryable=True
            )
        except requests.RequestException as error:
            logger.debug(
                f"DingTalk login token exchange failed: endpoint={token_url}, "
                f"error_type={type(error).__name__}"
            )
            return CapabilityExecutionResult.failed_result(
                "DingTalk login request failed", code="provider.request_failed", retryable=True
            )

        try:
            token_data = token_response.json()
        except ValueError:
            return CapabilityExecutionResult.failed_result(
                "DingTalk login response is invalid", code="provider.invalid_response"
            )

        if token_response.status_code != 200:
            return CapabilityExecutionResult.failed_result(
                token_data.get("message") or "DingTalk login failed",
                code="provider.auth_failed",
                external_code=str(token_data.get("code") or token_response.status_code),
            )

        # 钉钉 userAccessToken 响应仅含 accessToken/refreshToken/expireIn/corpId，
        # 不含 openId；openId 由第二步 contact/users/me 返回，这里只校验 accessToken
        access_token = token_data.get("accessToken", "")
        open_id = token_data.get("openId", "")
        if not access_token:
            return CapabilityExecutionResult.failed_result(
                "DingTalk login token is missing", code="provider.invalid_response"
            )

        # Step 2: 获取用户信息
        user_info_url = _get_config_value(config, "login_auth_user_info_url", DINGTALK_USER_INFO_URL)
        try:
            user_response = _get(
                user_info_url,
                headers={"x-acs-dingtalk-access-token": access_token},
            )
            user_data = user_response.json()
        except requests.Timeout:
            return CapabilityExecutionResult.failed_result(
                "DingTalk user info request timed out", code="provider.timeout", retryable=True
            )
        except (requests.RequestException, ValueError) as error:
            logger.debug(
                f"DingTalk user info request failed: endpoint={user_info_url}, "
                f"error_type={type(error).__name__}"
            )
            return CapabilityExecutionResult.failed_result(
                "DingTalk user info request failed", code="provider.request_failed", retryable=True
            )

        if user_response.status_code != 200:
            return CapabilityExecutionResult.failed_result(
                user_data.get("message") or "DingTalk user info fetch failed",
                code="provider.auth_failed",
                external_code=str(user_data.get("code") or user_response.status_code),
            )

        # 钉钉 contact/users/me 返回字段:
        # nick, avatarUrl, mobile, openId, unionId, email, employeeNo, stateCode 等
        return CapabilityExecutionResult.success_result(
            "DingTalk login authenticated",
            payload={
                "external_user": {
                    "open_id": user_data.get("openId") or open_id,
                    "openid": user_data.get("openId") or open_id,  # 兼容通用 fallback
                    "union_id": user_data.get("unionId", ""),
                    "nick": user_data.get("nick", ""),
                    "name": user_data.get("nick", ""),
                    "email": user_data.get("email", ""),
                    "mobile": user_data.get("mobile", ""),
                    "avatar_url": user_data.get("avatarUrl", ""),
                    "employee_no": user_data.get("employeeNo", ""),
                }
            },
        )
