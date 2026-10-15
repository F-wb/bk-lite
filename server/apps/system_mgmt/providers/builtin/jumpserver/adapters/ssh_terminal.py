"""JumpServer SSH 终端能力 Adapter

创建连接 Token，生成 Luna 终端 iframe URL。
"""

from apps.system_mgmt.providers.log import logger
from apps.system_mgmt.providers.runtime import CapabilityExecutionResult

from .client import JumpServerApiClient


class JumpServerSshTerminalAdapter:
    """JumpServer SSH 终端能力"""

    capability_key = "ssh_terminal"

    @classmethod
    def test_connection(cls, config: dict, provider_key: str, capability_key: str, **kwargs):
        base_url = (config or {}).get("base_url", "")
        api_key = (config or {}).get("api_key", "")
        api_secret = (config or {}).get("api_secret", "")

        if not base_url or not api_key or not api_secret:
            return CapabilityExecutionResult.failed_result(
                "JumpServer SSH terminal configuration is incomplete",
                code="provider.invalid_config",
                field="base_url" if not base_url else ("api_key" if not api_key else "api_secret"),
            )

        try:
            client = JumpServerApiClient(config)
            # 尝试查询资产列表验证权限
            response = client.get("/api/v1/assets/assets/", params={"limit": 1})
            if response.status_code == 200:
                return CapabilityExecutionResult.success_result(
                    "JumpServer SSH terminal capability is ready"
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
                f"JumpServer SSH terminal test failed with status {response.status_code}",
                code="provider.request_failed",
                retryable=True,
                external_code=str(response.status_code),
            )
        except Exception as error:
            logger.debug(
                "event=jumpserver_ssh_terminal_test_failed "
                "provider_key=%s error_type=%s",
                provider_key,
                type(error).__name__,
            )
            return CapabilityExecutionResult.failed_result(
                "JumpServer SSH terminal test failed",
                code="provider.request_failed",
                retryable=True,
            )

    @classmethod
    def create_terminal_session(cls, config: dict, provider_key: str, capability_key: str, **kwargs):
        """创建 SSH 终端会话。

        必需 kwargs:
            - username: 当前登录用户名
            - ip: 目标主机 IP
        可选 kwargs:
            - display_name: 用户显示名称
            - email: 用户邮箱
            - system_user: 指定系统账号（默认取配置）
        """
        username = kwargs.get("username", "")
        ip = kwargs.get("ip", "")
        display_name = kwargs.get("display_name", "") or username
        email = kwargs.get("email", "")

        if not username:
            return CapabilityExecutionResult.failed_result(
                "username is required",
                code="provider.invalid_config",
                field="username",
            )
        if not ip:
            return CapabilityExecutionResult.failed_result(
                "ip is required",
                code="provider.invalid_config",
                field="ip",
            )

        try:
            client = JumpServerApiClient(config)

            # 1. 查询资产
            asset = client.get_asset_by_ip(ip)
            if not asset:
                return CapabilityExecutionResult.failed_result(
                    f"Asset with IP or name {ip} not found in JumpServer",
                    code="provider.request_failed",
                    detail=f"asset_ip={ip}",
                )
            asset_id = asset.get("id")
            asset_name = asset.get("name", ip)
            logger.info(
                "event=jumpserver_asset_found provider_key=%s asset_id=%s asset_name=%s ip=%s",
                provider_key,
                asset_id,
                asset_name,
                ip,
            )

            # 2. 获取或创建用户
            auto_create = (config or {}).get("auto_create_user", True)
            if auto_create:
                user = client.get_or_create_user(username, display_name, email)
            else:
                user = client.get_user_by_username(username)
                if not user:
                    return CapabilityExecutionResult.failed_result(
                        f"User {username} not found in JumpServer and auto_create_user is disabled",
                        code="provider.request_failed",
                        detail=f"username={username}",
                    )
            user_id = user.get("id")
            logger.info(
                "event=jumpserver_user_resolved provider_key=%s user_id=%s username=%s",
                provider_key,
                user_id,
                username,
            )

            # 3. 选择系统账号（未命中即失败，不回退到其他账号）
            system_user = kwargs.get("system_user") or (config or {}).get("default_system_user", "root")
            accounts = client.get_asset_accounts(asset_id)
            system_user_id = None
            for account in accounts:
                if account.get("username") == system_user:
                    system_user_id = account.get("id")
                    break
            if not system_user_id:
                available_accounts = [account.get("username") for account in accounts]
                logger.warning(
                    "event=jumpserver_system_user_not_found provider_key=%s "
                    "requested=%s asset_id=%s available=%s",
                    provider_key,
                    system_user,
                    asset_id,
                    available_accounts,
                )
                return CapabilityExecutionResult.failed_result(
                    f"System user '{system_user}' not found on asset {asset_name}",
                    code="provider.system_user_not_found",
                    field="default_system_user",
                    detail=f"asset_id={asset_id}, available_accounts={available_accounts}",
                )

            # 4. 创建连接 Token
            expire_seconds = (config or {}).get("token_expire_seconds", 3600)
            token_data = client.create_connection_token(
                user_id=user_id,
                asset_id=asset_id,
                account_id=system_user_id,
                expire_seconds=expire_seconds,
            )
            token = token_data.get("id")
            if not token:
                return CapabilityExecutionResult.failed_result(
                    "JumpServer connection token is missing in response",
                    code="provider.invalid_response",
                )

            terminal_url = client.get_connection_token_url(token)
            logger.info(
                "event=jumpserver_terminal_session_created provider_key=%s "
                "user_id=%s asset_id=%s system_user=%s expire_seconds=%s",
                provider_key,
                user_id,
                asset_id,
                system_user,
                expire_seconds,
            )

            return CapabilityExecutionResult.success_result(
                "SSH terminal session created",
                payload={
                    "terminal_url": terminal_url,
                    "token": token,
                    "asset_name": asset_name,
                    "system_user": system_user,
                    "expire_seconds": expire_seconds,
                },
            )

        except Exception as error:
            logger.exception(
                "event=jumpserver_terminal_session_failed provider_key=%s "
                "username=%s ip=%s error_type=%s",
                provider_key,
                username,
                ip,
                type(error).__name__,
            )
            return CapabilityExecutionResult.failed_result(
                "Failed to create SSH terminal session",
                code="provider.request_failed",
                retryable=True,
                detail=str(error),
            )
