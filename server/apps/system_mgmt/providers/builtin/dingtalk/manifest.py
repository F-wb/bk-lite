from apps.system_mgmt.providers.schemas import ProviderManifest

PROVIDER_MANIFEST = ProviderManifest.model_validate(
    {
        "key": "dingtalk",
        "base_connection_adapter_key": "dingtalk.base_connection",
        "base_connection_adapter_path": "adapters.base_connection.DingtalkBaseConnectionAdapter",
        "name": "DingTalk",
        "description": "Built-in DingTalk (enterprise) integration provider for login auth.",
        "instance_templates": {
            "base_connection": {
                "title": "Base Connection",
                "groups": [
                    {
                        "key": "credentials",
                        "title": "App credentials",
                        "fields": [
                            {
                                "key": "app_key",
                                "label": "App Key",
                                "field_type": "string",
                                "required": True,
                                "placeholder": "dingxxxxxxxx",
                                "reset_capabilities": ["login_auth"],
                            },
                            {
                                "key": "app_secret",
                                "label": "App Secret",
                                "field_type": "password",
                                "required": True,
                                "secret": True,
                                "mask_strategy": "full",
                                "reset_capabilities": ["login_auth"],
                            },
                            {
                                "key": "corp_id",
                                "label": "Corp ID (Enterprise ID)",
                                "field_type": "string",
                                "required": False,
                                "placeholder": "dingxxxxxxxx",
                                "help_text": "企业代码，可选，用于标识企业",
                                "reset_capabilities": ["login_auth"],
                            },
                        ],
                    }
                ],
            }
        },
        "business_templates": {
            "login_auth_form": {
                "title": "Login authentication",
                "groups": [
                    {
                        "key": "mapping",
                        "title": "Field mapping",
                        "fields": [
                            {"key": "display_name", "label": "Display name", "field_type": "string", "required": True},
                            {"key": "icon", "label": "Icon", "field_type": "string", "required": False},
                            {"key": "description", "label": "Description", "field_type": "string", "required": False},
                            {"key": "external_field", "label": "External field", "field_type": "string", "required": True},
                            {"key": "platform_field", "label": "Platform field", "field_type": "select", "required": True},
                            {
                                "key": "unmatched_user_action",
                                "label": "Unmatched user action",
                                "field_type": "select",
                                "required": True,
                            },
                            {
                                "key": "default_group_name",
                                "label": "Default user group name",
                                "field_type": "string",
                                "required": False,
                            },
                        ],
                    }
                ],
                "available_external_fields": ["open_id", "union_id", "nick", "name", "email", "mobile", "employee_no"],
                "default_external_match_field": "open_id",
            }
        },
        "capabilities": [
            {
                "key": "login_auth",
                "name": "Login Auth",
                "description": "DingTalk enterprise login authentication capability.",
                "adapter_key": "dingtalk.login_auth",
                "adapter_path": "adapters.login_auth.DingtalkLoginAuthAdapter",
                "connection_template": [
                    {
                        "key": "login_auth_authorize_url",
                        "label": "Authorization URL",
                        "field_type": "string",
                        "required": False,
                        "default": "https://login.dingtalk.com/oauth2/auth",
                    },
                    {
                        "key": "login_auth_access_token_url",
                        "label": "User access token URL",
                        "field_type": "string",
                        "required": False,
                        "default": "https://api.dingtalk.com/v1.0/oauth2/userAccessToken",
                    },
                    {
                        "key": "login_auth_user_info_url",
                        "label": "User info URL",
                        "field_type": "string",
                        "required": False,
                        "default": "https://api.dingtalk.com/v1.0/contact/users/me",
                    },
                ],
                "business_template": "login_auth_form",
            }
        ],
    }
)
