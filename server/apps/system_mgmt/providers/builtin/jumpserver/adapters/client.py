"""JumpServer API HTTP 客户端

封装 JumpServer Admin API 的认证、请求、错误处理。
所有能力模块通过本模块发起 HTTP 请求，不直接调用 requests。
"""

import base64
import hashlib
import hmac
import json
from datetime import datetime, timezone
from email.utils import formatdate
from urllib.parse import urlencode, urljoin

import requests

try:
    from urllib3.exceptions import InsecureRequestWarning

    requests.packages.urllib3.disable_warnings(InsecureRequestWarning)
except Exception:  # pragma: no cover
    pass

JUMPSERVER_TIMEOUT = 15


def _get_verify_ssl(config: dict) -> bool:
    """是否校验 JumpServer 的 SSL 证书。内网自签名证书场景可关闭。"""
    value = (config or {}).get("verify_ssl", True)
    if isinstance(value, str):
        return value.strip().lower() not in ("false", "0", "no", "off")
    return bool(value)


def _get_base_url(config: dict) -> str:
    """提取并规范化 JumpServer base_url，确保不含尾部斜杠。"""
    base_url = (config or {}).get("base_url", "").rstrip("/")
    return base_url


def _join_url(base_url: str, path: str) -> str:
    """拼接 JumpServer API URL。"""
    if not base_url:
        return path
    return urljoin(base_url + "/", path.lstrip("/"))


def _extract_results(data):
    """兼容 JumpServer 的分页(dict)与非分页(list)两种返回结构。"""
    if isinstance(data, list):
        return data
    if isinstance(data, dict):
        return data.get("results") or []
    return []


def _build_auth_headers(api_key: str, api_secret: str) -> dict:
    """构建 JumpServer API 认证头（Signature 签名方式）。

    JumpServer v3+ 使用 Signature 认证：
    Authorization: Signature keyId="...", algorithm="hmac-sha256", headers="(request-target) date accept", signature="..."
    """
    date = formatdate(timeval=None, localtime=False, usegmt=True)
    accept = "application/json"

    # 构造签名字符串
    sign_string = f"(request-target): get /api/v1/users/profile/\ndate: {date}\naccept: {accept}"

    # HMAC-SHA256 签名
    signature = base64.b64encode(
        hmac.new(
            api_secret.encode("utf-8"),
            sign_string.encode("utf-8"),
            hashlib.sha256,
        ).digest()
    ).decode("utf-8")

    auth_header = (
        f'Signature keyId="{api_key}", algorithm="hmac-sha256", '
        f'headers="(request-target) date accept", signature="{signature}"'
    )

    return {
        "Authorization": auth_header,
        "Date": date,
        "Accept": accept,
        "Content-Type": "application/json",
    }


def _build_auth_headers_for_method(api_key: str, api_secret: str, method: str, path: str) -> dict:
    """为指定 HTTP 方法和路径构建认证头。"""
    date = formatdate(timeval=None, localtime=False, usegmt=True)
    accept = "application/json"

    sign_string = f"(request-target): {method.lower()} {path}\ndate: {date}\naccept: {accept}"

    signature = base64.b64encode(
        hmac.new(
            api_secret.encode("utf-8"),
            sign_string.encode("utf-8"),
            hashlib.sha256,
        ).digest()
    ).decode("utf-8")

    auth_header = (
        f'Signature keyId="{api_key}", algorithm="hmac-sha256", '
        f'headers="(request-target) date accept", signature="{signature}"'
    )

    return {
        "Authorization": auth_header,
        "Date": date,
        "Accept": accept,
        "Content-Type": "application/json",
    }


class JumpServerApiClient:
    """JumpServer Admin API 客户端"""

    def __init__(self, config: dict):
        self.base_url = _get_base_url(config)
        self.api_key = (config or {}).get("api_key", "")
        self.api_secret = (config or {}).get("api_secret", "")
        self.verify = _get_verify_ssl(config)
        self.timeout = JUMPSERVER_TIMEOUT

    def _request(self, method: str, path: str, **kwargs) -> requests.Response:
        """发起认证请求。

        JumpServer 的 Signature 认证要求 `(request-target)` 包含完整查询字符串，
        因此这里把 params 编码进 URL 参与签名，避免因签名串与真实请求不一致而 401。
        """
        params = kwargs.pop("params", None)
        query_string = urlencode(params, doseq=True) if params else ""
        signed_path = f"{path}?{query_string}" if query_string else path

        url = _join_url(self.base_url, signed_path)
        headers = _build_auth_headers_for_method(self.api_key, self.api_secret, method, signed_path)
        kwargs.setdefault("timeout", self.timeout)
        kwargs.setdefault("verify", self.verify)
        kwargs["headers"] = {**headers, **kwargs.pop("headers", {})}

        response = requests.request(method, url, **kwargs)
        return response

    def get(self, path: str, params: dict | None = None) -> requests.Response:
        return self._request("GET", path, params=params or {})

    def post(self, path: str, data: dict | None = None) -> requests.Response:
        return self._request("POST", path, json=data or {})

    def put(self, path: str, data: dict | None = None) -> requests.Response:
        return self._request("PUT", path, json=data or {})

    def delete(self, path: str) -> requests.Response:
        return self._request("DELETE", path)

    # ===== 用户相关 =====

    def get_user_by_username(self, username: str) -> dict | None:
        """按用户名查询用户。"""
        response = self.get("/api/v1/users/users/", params={"username": username})
        if response.status_code != 200:
            return None
        try:
            results = _extract_results(response.json())
        except ValueError:
            return None
        return results[0] if results else None

    def create_user(self, username: str, name: str, email: str = "", comment: str = "") -> dict:
        """创建用户。JumpServer 会自动分配默认角色，无需显式指定 system_roles。"""
        data = {
            "username": username,
            "name": name,
            "email": email or f"{username}@local",
            "comment": comment or "由盛大运维系统自动创建",
            "is_active": True,
        }
        response = self.post("/api/v1/users/users/", data=data)
        response.raise_for_status()
        return response.json()

    def get_or_create_user(self, username: str, name: str, email: str = "") -> dict:
        """获取或创建用户。"""
        user = self.get_user_by_username(username)
        if user:
            return user
        return self.create_user(username, name, email)

    # ===== 资产相关 =====

    def get_asset_by_ip(self, ip: str) -> dict | None:
        """按 IP 查询资产。

        先用 JumpServer 的 address 字段精确匹配；未命中时退化为按 name 匹配，兼容
        「堡垒机资产以主机 IP 命名、实际连接地址为网关映射地址（如宿主机 IP:2222）」
        的部署场景。两次查询都要求 address 或 name 与 IP 精确相等，避免误选无关资产。
        """
        for params in ({"address": ip}, {"search": ip}):
            response = self.get("/api/v1/assets/assets/", params=params)
            if response.status_code != 200:
                continue
            try:
                results = _extract_results(response.json())
            except ValueError:
                continue
            for asset in results:
                if asset.get("address") == ip or asset.get("name") == ip:
                    return asset
        return None

    def get_asset_accounts(self, asset_id: str) -> list[dict]:
        """查询资产可用的系统账号（/api/v1/accounts/accounts/?asset=<id>）。"""
        response = self.get("/api/v1/accounts/accounts/", params={"asset": asset_id})
        if response.status_code != 200:
            return []
        try:
            return _extract_results(response.json())
        except ValueError:
            return []

    # ===== 连接 Token =====

    def create_connection_token(
        self,
        user_id: str,
        asset_id: str,
        account_id: str,
        expire_seconds: int = 3600,
    ) -> dict:
        """创建连接 Token。

        JumpServer 要求字段 account/protocol/connect_method 齐全。account 不是账号名，
        而是「账号别名」：真实账号的别名即其 id(UUID)，虚拟账号为 @INPUT/@USER 等。
        JumpServer 用它匹配「该用户在本资产上被授权的账号」，传账号名（如 root）会返回
        400 perm_account_invalid（账号未找到）。
        响应体中令牌的 UUID 主键位于 id 字段（Luna 终端 URL 用的就是它）。
        """
        data = {
            "user": user_id,
            "asset": asset_id,
            "account": account_id,
            "protocol": "ssh",
            "connect_method": "web_cli",
            "expire_seconds": expire_seconds,
        }
        response = self.post("/api/v1/authentication/connection-token/", data=data)
        response.raise_for_status()
        return response.json()

    def get_connection_token_url(self, token_id: str) -> str:
        """构建 Luna 终端连接 URL。

        与 Luna 前端 connect 逻辑保持一致：路由为 /luna/koko/connect/，
        query 为 ?token=<连接令牌 id>&protocol=ssh。
        注意 token 必须取连接令牌的 id（UUID），而不是 value（短随机串）。
        """
        return f"{self.base_url}/luna/koko/connect/?token={token_id}&protocol=ssh"
