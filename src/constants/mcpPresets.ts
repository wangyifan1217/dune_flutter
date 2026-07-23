import type { McpServerConfig } from "../types/agent";

export interface McpPreset {
  id: string;
  name: string;
  title: string;
  description: string;
  category: "thinking" | "files" | "office";
  /** 根据当前工作区生成配置；不依赖 Node.js / Python / Office */
  build: (workspace: string | null | undefined) => McpServerConfig;
}

function allowedDir(workspace: string | null | undefined): string {
  const w = workspace?.trim();
  if (w) return w.replace(/\\/g, "/");
  // 无项目时仍给一个可编辑占位；用户可在「编辑」里改路径
  return ".";
}

/**
 * command 使用 nova-builtin，由桌面端在启动 Agent 时展开为
 * `nova-desktop.exe --mcp-server …`，用户无需安装 Node.js。
 */
export const MCP_PRESETS: McpPreset[] = [
  {
    id: "sequential-thinking",
    name: "sequential-thinking",
    title: "Sequential Thinking",
    description: "复杂问题分步推理，适合排错、方案对比、长任务拆解（应用内置）",
    category: "thinking",
    build: () => ({
      name: "sequential-thinking",
      command: "nova-builtin",
      args: ["sequential-thinking"],
      env: [],
    }),
  },
  {
    id: "filesystem",
    name: "filesystem",
    title: "Filesystem",
    description: "在指定目录内读写文件（默认当前项目，应用内置）",
    category: "files",
    build: (workspace) => ({
      name: "filesystem",
      command: "nova-builtin",
      args: ["filesystem", allowedDir(workspace)],
      env: [],
    }),
  },
  {
    id: "memory",
    name: "memory",
    title: "Memory",
    description: "本地笔记记忆，适合记住项目约定与文件要点（应用内置）",
    category: "files",
    build: () => ({
      name: "memory",
      command: "nova-builtin",
      args: ["memory"],
      env: [],
    }),
  },
  {
    id: "fetch",
    name: "fetch",
    title: "Fetch",
    description: "抓取网页 / URL 文本内容（应用内置，无需 npx）",
    category: "files",
    build: () => ({
      name: "fetch",
      command: "nova-builtin",
      args: ["fetch"],
      env: [],
    }),
  },
  {
    id: "excel",
    name: "excel",
    title: "Excel",
    description: "读写 / 创建 .xlsx（应用内置，无需安装 Office）",
    category: "office",
    build: () => ({
      name: "excel",
      command: "nova-builtin",
      args: ["excel"],
      env: [],
    }),
  },
  {
    id: "word",
    name: "word",
    title: "Word",
    description: "创建 / 读取 / 追加 .docx（应用内置，无需安装 Office）",
    category: "office",
    build: () => ({
      name: "word",
      command: "nova-builtin",
      args: ["word"],
      env: [],
    }),
  },
  {
    id: "powerpoint",
    name: "powerpoint",
    title: "PowerPoint",
    description: "创建 / 读取 .pptx 幻灯片（应用内置，无需安装 Office）",
    category: "office",
    build: () => ({
      name: "powerpoint",
      command: "nova-builtin",
      args: ["powerpoint"],
      env: [],
    }),
  },
];

export function presetAlreadyAdded(
  servers: McpServerConfig[],
  preset: McpPreset,
): boolean {
  return servers.some((s) => s.name === preset.name);
}
