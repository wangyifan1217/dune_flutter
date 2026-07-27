import type { ChatMessage, DirectoryTreeNode, McpServerConfig } from "../types/agent";

export type RightTab = "files" | "diff" | "terminal" | "activity" | "preview";
export type LeftMode = "threads" | "settings";

export interface ThreadSession {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messages: ChatMessage[];
  /** Workspace path when the session was created / last bound. */
  workspace?: string | null;
  /** 当前会话对话模式 */
  chatMode?: "agent" | "plan" | "ask";
}

export interface DiffHunk {
  id: string;
  path: string;
  summary: string;
  content: string;
}

export interface ActivityItem {
  id: string;
  text: string;
  at: number;
}

export interface CodexUiState {
  leftMode: LeftMode;
  rightOpen: boolean;
  rightTab: RightTab;
  sessions: ThreadSession[];
  activeSessionId: string | null;
  tree: DirectoryTreeNode | null;
  diffs: DiffHunk[];
  activity: ActivityItem[];
}

export const emptySettingsMcp = (): McpServerConfig[] => [];
