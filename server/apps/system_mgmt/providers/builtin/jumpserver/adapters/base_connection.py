"""JumpServer 基础连接校验 Adapter

校验 JumpServer 服务可达性和 API 凭证有效性。
"""

import requests

from apps.system_mgmt.providers.log import logger
from apps.system_mgmt.providers.runtime import CapabilityExecutionResult

from .client import (
    JUMPSERVER_TIMEOUT,
    _build_auth_headers,
    _get_base_url,
    _get_verify_ssl,
    _join_url,
)


class JumpServerBaseConnectionAdapter:
    """JumpServer 基础连接校验"""

    @classmethod
    def test_connection(cls, config: dict, provider_key: str, capability_key: str, **kwargs):
        base_url = _get_base_url(config)
        api_key = (config or {}).get("api_key", "")
        api_secret = (config or {}).get("api_secret", "")

        if not base_url:
            return CapabilityExecutionResult.failed_result(
                "JumpServer base_url is missing",
                code="provider.invalid_config",
                field="base_url",
            )
        if not api_key:
            return CapabilityExecutionResult.failed_result(
                "JumpServer api_key is missing",
                code="provider.invalid_config",
                field="api_key",
            )
        if not api_secret:
            return CapabilityExecutionResult.failed_result(
                "JumpServer api_secret is missing",
                code="provider.invalid_config",
                field="api_secret",
            )

        # 校验服务可达性：尝试获取当前用户信息
        try:
            headers = _build_auth_headers(api_key, api_secret)
            url = _join_url(base_url, "/api/v1/users/profile/")
            response = requests.get(
                url,
                headers=headers,
                timeout=JUMPSERVER_TIMEOUT,
                verify=_get_verify_ssl(config),
            )

            if response.status_code == 200:
                profile = response.json()
                username = profile.get("username", "")
                logger.info(
                    "event=jumpserver_base_connection_test_success "
                    "provider_key=%s username=%s",
                    provider_key,
                    username,
                )
                return CapabilityExecutionResult.success_result(
                    f"JumpServer connection test succeeded, connected as {username}",
                    payload={"username": username},
                )

            if response.status_code == 401:
                return CapabilityExecutionResult.failed_result(
                    "JumpServer API key or secret is invalid",
                    code="provider.auth_failed",
                    external_code=str(response.status_code),
                )

            if response.status_code == 403:
                return CapabilityExecutionResult.failed_result(
                    "JumpServer API key has insufficient permissions (admin required)",
                    code="provider.permission_denied",
                    external_code=str(response.status_code),
                )

            return CapabilityExecutionResult.failed_result(
                f"JumpServer connection failed with status {response.status_code}",
                code="provider.request_failed",
                retryable=True,
                external_code=str(response.status_code),
            )

        except requests.Timeout:
            return CapabilityExecutionResult.failed_result(
                "JumpServer connection timed out",
                code="provider.timeout",
                retryable=True,
            )
        except requests.RequestException as error:
            logger.debug(
                "event=jumpserver_base_connection_test_failed "
                "provider_key=%s error_type=%s",
                provider_key,
                type(error).__name__,
            )
            return CapabilityExecutionResult.failed_result(
                "JumpServer connection request failed",
                code="provider.request_failed",
                retryable=True,
            )
