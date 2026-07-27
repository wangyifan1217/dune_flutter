import { invoke } from "@tauri-apps/api/core";
import { useEffect, useState } from "react";
import type { DirectoryTreeNode, FileEntry } from "../types/agent";
import { IconChevronRight, IconFile, IconFolder } from "./Icons";

interface FileTreeProps {
  tree: DirectoryTreeNode | null;
  selectedPath?: string | null;
  onOpenFile?: (path: string) => void;
}

function samePath(a: string, b: string) {
  const norm = (p: string) =>
    p
      .replace(/^\\\\\?\\/i, "")
      .replace(/\\/g, "/")
      .replace(/\/+$/, "")
      .toLowerCase();
  return norm(a) === norm(b);
}

/** 按工作区根路径缓存展开与懒加载结果，关闭面板/切 tab 后再回来仍保留 */
const treeUiCache = new Map<
  string,
  {
    expanded: string[];
    loadedChildren: Record<string, DirectoryTreeNode[]>;
  }
>();

function resolveChildren(
  node: DirectoryTreeNode,
  loadedChildren: Record<string, DirectoryTreeNode[]>,
): DirectoryTreeNode[] | undefined {
  // build_tree 深度耗尽时 children 为 null（未加载），不能当成空数组
  if (Array.isArray(node.children)) return node.children;
  return loadedChildren[node.path];
}

function TreeNode({
  node,
  depth = 0,
  selectedPath,
  onOpenFile,
  expanded,
  loadedChildren,
  loadingPaths,
  onToggleFolder,
}: {
  node: DirectoryTreeNode;
  depth?: number;
  selectedPath?: string | null;
  onOpenFile?: (path: string) => void;
  expanded: Set<string>;
  loadedChildren: Record<string, DirectoryTreeNode[]>;
  loadingPaths: Set<string>;
  onToggleFolder: (node: DirectoryTreeNode) => void;
}) {
  const clickable = node.isDir || Boolean(onOpenFile);
  const children = resolveChildren(node, loadedChildren);
  const isExpanded = expanded.has(node.path);
  const isLoading = loadingPaths.has(node.path);
  const isSelected =
    !node.isDir && Boolean(selectedPath) && samePath(node.path, selectedPath!);

  return (
    <div className="tree-node">
      <button
        type="button"
        className={`tree-row ${clickable ? "clickable" : ""} ${isSelected ? "selected" : ""}`}
        style={{ paddingLeft: `${depth * 14 + 4}px` }}
        disabled={!clickable}
        onClick={() => {
          if (node.isDir) onToggleFolder(node);
          else onOpenFile?.(node.path);
        }}
        title={node.path}
      >
        {node.isDir ? (
          <span className={`tree-chev ${isExpanded ? "open" : ""}`} aria-hidden>
            <IconChevronRight size={12} />
          </span>
        ) : (
          <span className="tree-chev spacer" aria-hidden />
        )}
        <span className="tree-icon" aria-hidden>
          {node.isDir ? <IconFolder size={14} /> : <IconFile size={14} />}
        </span>
        <span className="tree-name">{node.name}</span>
      </button>
      {node.isDir && isExpanded ? (
        isLoading && children === undefined ? (
          <div
            className="tree-loading"
            style={{ paddingLeft: `${(depth + 1) * 14 + 4}px` }}
          >
            加载中…
          </div>
        ) : (
          children?.map((child) => (
            <TreeNode
              key={child.path}
              node={child}
              depth={depth + 1}
              selectedPath={selectedPath}
              onOpenFile={onOpenFile}
              expanded={expanded}
              loadedChildren={loadedChildren}
              loadingPaths={loadingPaths}
              onToggleFolder={onToggleFolder}
            />
          ))
        )
      ) : null}
    </div>
  );
}

function restoreState(rootPath: string): {
  expanded: Set<string>;
  loadedChildren: Record<string, DirectoryTreeNode[]>;
} {
  const cached = treeUiCache.get(rootPath);
  if (cached) {
    return {
      expanded: new Set(cached.expanded),
      loadedChildren: cached.loadedChildren,
    };
  }
  return {
    expanded: new Set([rootPath]),
    loadedChildren: {},
  };
}

export function FileTree({ tree, selectedPath = null, onOpenFile }: FileTreeProps) {
  const rootPath = tree?.path ?? "";
  const initial = rootPath ? restoreState(rootPath) : null;

  const [expanded, setExpanded] = useState<Set<string>>(
    () => initial?.expanded ?? new Set(),
  );
  const [loadedChildren, setLoadedChildren] = useState<
    Record<string, DirectoryTreeNode[]>
  >(() => initial?.loadedChildren ?? {});
  const [loadingPaths, setLoadingPaths] = useState<Set<string>>(new Set());

  // 仅在工作区根路径变化时恢复/重置；同一项目刷新 tree 对象不丢展开
  useEffect(() => {
    if (!tree) return;
    const next = restoreState(tree.path);
    setExpanded(next.expanded);
    setLoadedChildren(next.loadedChildren);
    setLoadingPaths(new Set());
  }, [tree?.path]);

  useEffect(() => {
    if (!rootPath) return;
    treeUiCache.set(rootPath, {
      expanded: [...expanded],
      loadedChildren,
    });
  }, [rootPath, expanded, loadedChildren]);

  async function toggleFolder(node: DirectoryTreeNode) {
    if (expanded.has(node.path)) {
      setExpanded((current) => {
        const next = new Set(current);
        next.delete(node.path);
        return next;
      });
      return;
    }

    setExpanded((current) => new Set(current).add(node.path));

    const alreadyLoaded =
      Array.isArray(node.children) || Array.isArray(loadedChildren[node.path]);
    if (alreadyLoaded) return;

    setLoadingPaths((current) => new Set(current).add(node.path));
    try {
      const entries = await invoke<FileEntry[]>("list_workspace", {
        path: node.path,
      });
      setLoadedChildren((current) => ({
        ...current,
        [node.path]: entries.map((entry) => ({
          name: entry.name,
          path: entry.path,
          isDir: entry.isDir,
        })),
      }));
    } catch {
      setExpanded((current) => {
        const next = new Set(current);
        next.delete(node.path);
        return next;
      });
    } finally {
      setLoadingPaths((current) => {
        const next = new Set(current);
        next.delete(node.path);
        return next;
      });
    }
  }

  if (!tree) {
    return <div className="empty-state">打开文件夹后即可浏览文件</div>;
  }

  return (
    <div className="file-tree">
      <TreeNode
        node={tree}
        selectedPath={selectedPath}
        onOpenFile={onOpenFile}
        expanded={expanded}
        loadedChildren={loadedChildren}
        loadingPaths={loadingPaths}
        onToggleFolder={(node) => void toggleFolder(node)}
      />
    </div>
  );
}
