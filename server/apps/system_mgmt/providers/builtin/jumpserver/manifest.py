"""JumpServer 堡垒机集成 Provider

提供 SSH 终端连接能力，通过 JumpServer Admin API 创建连接 Token，
前端以新标签页打开 Luna 终端实现 Web SSH。
"""

from apps.system_mgmt.providers.schemas import ProviderManifest

PROVIDER_MANIFEST = ProviderManifest.model_validate(
    {
        "key": "jumpserver",
        "base_connection_adapter_key": "jumpserver.base_connection",
        "base_connection_adapter_path": "adapters.base_connection.JumpServerBaseConnectionAdapter",
        "name": "JumpServer",
        "description": "JumpServer 堡垒机 SSH 终端集成",
        "instance_templates": {
            "base_connection": {
                "title": "Base Connection",
                "groups": [
                    {
                        "key": "connection",
                        "title": "服务连接",
                        "fields": [
                            {
                                "key": "base_url",
                                "label": "JumpServer 地址",
                                "field_type": "string",
                                "required": True,
                                "placeholder": "https://jumpserver.example.com",
                                "help_text": "JumpServer 服务地址，不含尾部斜杠",
                            },
                            {
                                "key": "api_key",
                                "label": "API Key",
                                "field_type": "password",
                                "required": True,
                                "secret": True,
                                "mask_strategy": "full",
                                "help_text": "JumpServer Admin API Key（Access Key）",
                            },
                            {
                                "key": "api_secret",
                                "label": "API Secret",
                                "field_type": "password",
                                "required": True,
                                "secret": True,
                                "mask_strategy": "full",
                                "help_text": "JumpServer Admin API Secret",
                            },
                            {
                                "key": "verify_ssl",
                                "label": "校验 SSL 证书",
                                "field_type": "boolean",
                                "required": False,
                                "default": True,
                                "help_text": "如 JumpServer 使用自签名证书导致连接失败，请关闭此项",
                            },
                        ],
                    },
                    {
                        "key": "terminal",
                        "title": "终端配置",
                        "fields": [
                            {
                                "key": "default_system_user",
                                "label": "默认系统账号",
                                "field_type": "string",
                                "required": False,
                                "default": "root",
                                "help_text": "SSH 登录默认使用的系统账号",
                            },
                            {
                                "key": "token_expire_seconds",
                                "label": "Token 过期时间（秒）",
                                "field_type": "number",
                                "required": False,
                                "default": 3600,
                                "help_text": "连接 Token 过期时间，默认 3600 秒",
                            },
                            {
                                "key": "auto_create_user",
                                "label": "自动创建用户",
                                "field_type": "boolean",
                                "required": False,
                                "default": True,
                                "help_text": "用户首次连接时自动在 JumpServer 创建账号",
                            },
                        ],
                    },
                ],
            }
        },
        "capabilities": [
            {
                "key": "ssh_terminal",
                "name": "SSH 终端",
                "description": "通过 JumpServer Luna 提供 Web SSH 终端连接能力",
                "adapter_key": "jumpserver.ssh_terminal",
                "adapter_path": "adapters.ssh_terminal.JumpServerSshTerminalAdapter",
            },
            {
                "key": "asset_query",
                "name": "资产查询",
                "description": "按 IP 查询 JumpServer 资产信息",
                "adapter_key": "jumpserver.asset_query",
                "adapter_path": "adapters.asset.JumpServerAssetAdapter",
            },
        ],
    }
)
