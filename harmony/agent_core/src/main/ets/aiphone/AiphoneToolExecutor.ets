import { aiphoneErrorJsonl } from './AiphoneA2ui';
import { isRegisteredAiphoneToolId } from './AiphoneToolDefinitions';

function unsupportedToolJsonl(toolId: string, surfaceId: string): string {
  const body = toolId === 'dynamic.search'
    ? 'dynamic.search 已注册，但 Loopy 尚未迁移 AIPhoneDemo 的动态工具目录和 MCP 执行器；不会伪造发现或工具结果。'
    : toolId + ' 已注册，但 Loopy 尚未迁移该真实 provider 执行器；不会返回模拟数据。';
  return aiphoneErrorJsonl(surfaceId, 'AIPhone 工具尚未迁移', body);
}

export async function runAiphoneTool(
  toolId: string,
  _prompt: string,
  surfaceId: string,
  _actionId: string,
  _args: Object | null = null
): Promise<string> {
  if (!isRegisteredAiphoneToolId(toolId)) {
    return aiphoneErrorJsonl(surfaceId, '未知 AIPhone 工具', '未注册 AIPhone 工具：' + toolId);
  }

  if (toolId === 'gmail.message.send') {
    return aiphoneErrorJsonl(
      surfaceId,
      'UnsafeActionBlocked',
      'UnsafeActionBlocked：不会自动发送 Gmail。请先查看草稿内容，确认收件人和正文后，创建或打开 Gmail 草稿由用户手动发送。'
    );
  }

  if (toolId === 'social.reply.send') {
    return aiphoneErrorJsonl(
      surfaceId,
      '微信回复未发送',
      'social.reply.send 已注册为真实本地动作，但当前 HAP 未接入可执行的微信辅助发送器；不会假装发送成功。'
    );
  }

  return unsupportedToolJsonl(toolId, surfaceId);
}
