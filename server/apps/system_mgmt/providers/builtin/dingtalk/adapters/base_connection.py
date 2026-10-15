from apps.system_mgmt.providers.runtime import CapabilityExecutionResult


class DingtalkBaseConnectionAdapter:
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
        return CapabilityExecutionResult.success_result("DingTalk base configuration is complete")
