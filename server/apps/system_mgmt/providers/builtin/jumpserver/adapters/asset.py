"""JumpServer 资产查询能力 Adapter

按 IP 查询 JumpServer 资产信息。
"""

from apps.system_mgmt.providers.log import logger
from apps.system_mgmt.providers.runtime import CapabilityExecutionResult

from .client import JumpServerApiClient


class JumpServerAssetAdapter:
    """JumpServer 资产查询能力"""

    capability_key = "asset_query"

    @classmethod
    def test_connection(cls, config: dict, provider_key: str, capability_key: str, **kwargs):
        base_url = (config or {}).get("base_url", "")
        api_key = (config or {}).get("api_key", "")
        api_secret = (config or {}).get("api_secret", "")

        if not base_url or not api_key or not api_secret:
            return CapabilityExecutionResult.failed_result(
                "JumpServer asset query configuration is incomplete",
                code="provider.invalid_config",
                field="base_url" if not base_url else ("api_key" if not api_key else "api_secret"),
            )

        try:
            client = JumpServerApiClient(config)
            response = client.get("/api/v1/assets/assets/", params={"limit": 1})
            if response.status_code == 200:
                return CapabilityExecutionResult.success_result(
                    "JumpServer asset query capability is ready"
                )
            if response.status_code == 401:
                return CapabilityExecutionResult.failed_result(
                    "JumpServer API key or secret is invalid",
                    code="provider.auth_failed",
                    external_code=str(response.status_code),
                )
            if response.status_code == 403:
                return CapabilityExecutionResult.failed_result(
                    "JumpServer API key has insufficient permissions",
                    code="provider.permission_denied",
                    external_code=str(response.status_code),
                )
            return CapabilityExecutionResult.failed_result(
                f"JumpServer asset query test failed with status {response.status_code}",
                code="provider.request_failed",
                retryable=True,
                external_code=str(response.status_code),
            )
        except Exception as error:
            logger.debug(
                "event=jumpserver_asset_query_test_failed "
                "provider_key=%s error_type=%s",
                provider_key,
                type(error).__name__,
            )
            return CapabilityExecutionResult.failed_result(
                "JumpServer asset query test failed",
                code="provider.request_failed",
                retryable=True,
            )

    @classmethod
    def query_asset(cls, config: dict, provider_key: str, capability_key: str, **kwargs):
        """按 IP 查询资产。

        必需 kwargs:
            - ip: 目标主机 IP
        """
        ip = kwargs.get("ip", "")
        if not ip:
            return CapabilityExecutionResult.failed_result(
                "ip is required",
                code="provider.invalid_config",
                field="ip",
            )

        try:
            client = JumpServerApiClient(config)
            asset = client.get_asset_by_ip(ip)
            if not asset:
                return CapabilityExecutionResult.failed_result(
                    f"Asset with IP or name {ip} not found",
                    code="provider.request_failed",
                    detail=f"asset_ip={ip}",
                )

            return CapabilityExecutionResult.success_result(
                "Asset found",
                payload={
                    "asset": {
                        "id": asset.get("id"),
                        "name": asset.get("name"),
                        "ip": asset.get("address") or asset.get("ip"),
                        "platform": asset.get("platform", {}).get("name", ""),
                        "protocols": asset.get("protocols", []),
                        "is_active": asset.get("is_active", False),
                        "comment": asset.get("comment", ""),
                    }
                },
            )
        except Exception as error:
            logger.exception(
                "event=jumpserver_asset_query_failed provider_key=%s "
                "ip=%s error_type=%s",
                provider_key,
                ip,
                type(error).__name__,
            )
            return CapabilityExecutionResult.failed_result(
                "Failed to query asset",
                code="provider.request_failed",
                retryable=True,
                detail=str(error),
            )
