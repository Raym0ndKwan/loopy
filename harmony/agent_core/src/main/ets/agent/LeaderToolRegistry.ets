import { common } from '@kit.AbilityKit';
import { SandboxFileWriteTool } from '../file/SandboxFileWriteTool';
import { CreateUiTaskTool } from './CreateUiTaskTool';
import { MessageBus } from './MessageBus';
import { TimeTool } from './TimeTool';
import { ToolRegistry } from './ToolRegistry';

export function createLeaderToolRegistry(
  context: common.UIAbilityContext,
  bus: MessageBus
): ToolRegistry {
  const registry = new ToolRegistry();
  registry.register(new CreateUiTaskTool(bus));
  registry.register(new TimeTool());
  registry.register(new SandboxFileWriteTool(context));
  return registry;
}
