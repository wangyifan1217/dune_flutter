import { invoke } from "@tauri-apps/api/core";
import { useEffect, useState } from "react";
import type { DirectoryTreeNode, FileEntry } from "../types/agent";
import { IconChevronRight, IconFile, IconFolder } from "./Icons";

interface FileTreeProps {
  tree: DirectoryTreeNode | null;
  onOpenFile?: (path: string) => void;
}

function TreeNode({
  node,
  depth = 0,
  onOpenFile,
  expanded,
  loadedChildren,
  onToggleFolder,
}: {
  node: DirectoryTreeNode;
  depth?: number;
  onOpenFile?: (path: string) => void;
  expanded: Set<string>;
  loadedChildren: Record<string, DirectoryTreeNode[]>;
  onToggleFolder: (node: DirectoryTreeNode) => void;
}) {
  const clickable = node.isDir || Boolean(onOpenFile);
  const children = node.children ?? loadedChildren[node.path];
  const isExpanded = expanded.has(node.path);

  return (
    <div className="tree-node">
      <button
        type="button"
        className={`tree-row ${clickable ? "clickable" : ""}`}
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
      {node.isDir && isExpanded && children?.map((child) => (
        <TreeNode
          key={child.path}
          node={child}
          depth={depth + 1}
          onOpenFile={onOpenFile}
          expanded={expanded}
          loadedChildren={loadedChildren}
          onToggleFolder={onToggleFolder}
        />
      ))}
    </div>
  );
}

export function FileTree({ tree, onOpenFile }: FileTreeProps) {
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [loadedChildren, setLoadedChildren] = useState<Record<string, DirectoryTreeNode[]>>({});

  useEffect(() => {
    if (!tree) return;
    const initial = new Set<string>();
    const addExpanded = (node: DirectoryTreeNode) => {
      if (!node.isDir) return;
      initial.add(node.path);
      node.children?.forEach(addExpanded);
    };
    addExpanded(tree);
    setExpanded(initial);
    setLoadedChildren({});
  }, [tree]);

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
    if (node.children !== undefined || loadedChildren[node.path] !== undefined) return;
    try {
      const entries = await invoke<FileEntry[]>("list_workspace", { path: node.path });
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
    }
  }

  if (!tree) {
    return <div className="empty-state">打开文件夹后即可浏览文件</div>;
  }

  return (
    <div className="file-tree">
      <TreeNode
        node={tree}
        onOpenFile={onOpenFile}
        expanded={expanded}
        loadedChildren={loadedChildren}
        onToggleFolder={(node) => void toggleFolder(node)}
      />
    </div>
  );
}
