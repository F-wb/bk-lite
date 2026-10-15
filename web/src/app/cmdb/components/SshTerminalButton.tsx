import React, { useState } from 'react';
import { Button, message } from 'antd';
import { CodeOutlined } from '@ant-design/icons';
import { useTranslation } from '@/utils/i18n';
import { useUserInfoContext } from '@/context/userInfo';
import { useAuth } from '@/context/auth';
import { isIpamModel } from '@/app/cmdb/constants/ipam';

interface SshTerminalButtonProps {
  instDetail: Record<string, any>;
  modelId: string;
}

/**
 * SSH 终端连接按钮
 * 实例存在 IP 地址且非 IPAM 网段模型时显示（不限于 host 模型，虚拟机等其他资产模型同样适用）
 *
 * 堡垒机终端页面（Luna/Koko）依赖浏览器携带堡垒机会话 Cookie，而该 Cookie 为
 * SameSite=Lax，在跨站 iframe 中不会被发送，会导致终端报「无法连接 Koko」。
 * 因此这里以新标签页（顶层导航）方式打开终端。
 */
const SshTerminalButton: React.FC<SshTerminalButtonProps> = ({ instDetail, modelId }) => {
  const { t } = useTranslation();
  const { username, displayName } = useUserInfoContext();
  const { token } = useAuth();
  const [loading, setLoading] = useState(false);

  // 排除 IPAM 网段模型；其余模型只要有 IP 即显示
  const ip = instDetail?.ip_addr || instDetail?.ip || '';
  if (isIpamModel(modelId) || !ip) {
    return null;
  }

  const handleOpenTerminal = async () => {
    if (!token) {
      message.error('登录态已失效，请重新登录后重试');
      return;
    }
    // 先同步打开空白标签页，避免异步请求返回后被浏览器拦截
    const tab = window.open('about:blank', '_blank');
    setLoading(true);
    try {
      // 调用后端 API 创建 SSH 终端会话
      const response = await fetch('/api/v1/system_mgmt/integration_instance/execute_capability/', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          provider_key: 'jumpserver',
          capability_key: 'ssh_terminal',
          operation: 'create_terminal_session',
          params: {
            username: username || '',
            display_name: displayName || username || '',
            email: '',
            ip,
          },
        }),
      });

      const body = await response.json();
      // 平台统一响应信封 { result, code, message, data }，真实内容在 data 内；兼容无信封的扁平结构
      const result = body?.data ?? body;

      if (!response.ok || body?.result === false || !result?.success) {
        const errorMsg =
          result?.summary ||
          result?.errors?.[0]?.message ||
          body?.message ||
          '创建 SSH 终端会话失败';
        message.error(errorMsg);
        tab?.close();
        return;
      }

      const url = result?.payload?.terminal_url;
      if (!url) {
        message.error('终端 URL 获取失败');
        tab?.close();
        return;
      }

      if (tab) {
        tab.location.href = url;
      } else {
        window.open(url, '_blank');
      }
    } catch (error) {
      message.error('SSH 终端连接请求失败');
      tab?.close();
    } finally {
      setLoading(false);
    }
  };

  return (
    <Button
      size="small"
      icon={<CodeOutlined />}
      loading={loading}
      onClick={handleOpenTerminal}
    >
      {t('cmdb.sshTerminal', 'SSH 终端')}
    </Button>
  );
};

export default SshTerminalButton;
