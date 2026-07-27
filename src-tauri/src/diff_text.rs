//! 简易按行 unified diff，供写文件后在会话里展示。

use std::cmp;

const MAX_CONTEXT_LINES: usize = 3;
const MAX_DIFF_LINES: usize = 400;

/// 写文件结果：是否新建 + unified diff 文本。
#[derive(Debug, Clone)]
pub struct WriteFileDiff {
    pub created: bool,
    pub diff: String,
}

/// 生成简易 unified diff（无外部依赖）。大变更会截断。
pub fn unified_line_diff(old: &str, new: &str, path: &str) -> String {
    let old_lines: Vec<&str> = split_lines(old);
    let new_lines: Vec<&str> = split_lines(new);

    if old_lines == new_lines {
        return format!("--- a/{path}\n+++ b/{path}\n@@ 无变更 @@\n");
    }

    // 限制规模，避免 O(n*m) 爆内存
    let old_capped = cap_lines(&old_lines, 2500);
    let new_capped = cap_lines(&new_lines, 2500);
    let ops = diff_ops(&old_capped, &new_capped);

    let mut out = String::new();
    out.push_str(&format!("--- a/{path}\n+++ b/{path}\n"));

    let hunks = group_hunks(&ops, MAX_CONTEXT_LINES);
    let mut emitted = 0usize;
    let mut truncated = false;

    for hunk in hunks {
        if emitted >= MAX_DIFF_LINES {
            truncated = true;
            break;
        }
        let header = format!(
            "@@ -{},{} +{},{} @@\n",
            hunk.old_start.max(1),
            hunk.old_count,
            hunk.new_start.max(1),
            hunk.new_count
        );
        out.push_str(&header);
        for line in hunk.lines {
            if emitted >= MAX_DIFF_LINES {
                truncated = true;
                break;
            }
            out.push_str(&line);
            if !line.ends_with('\n') {
                out.push('\n');
            }
            emitted += 1;
        }
    }

    if truncated {
        out.push_str(&format!(
            "\n…（diff 已截断，仅显示前 {MAX_DIFF_LINES} 行变更）\n"
        ));
    } else if old_lines.len() > old_capped.len() || new_lines.len() > new_capped.len() {
        out.push_str("\n…（文件过长，仅对前部行计算 diff）\n");
    }

    out
}

fn split_lines(text: &str) -> Vec<&str> {
    if text.is_empty() {
        return Vec::new();
    }
    // 保留无尾换行的最后一行
    let mut lines: Vec<&str> = text.split('\n').collect();
    if text.ends_with('\n') {
        lines.pop();
    }
    lines
}

fn cap_lines<'a>(lines: &[&'a str], max: usize) -> Vec<&'a str> {
    if lines.len() <= max {
        lines.to_vec()
    } else {
        lines[..max].to_vec()
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Op {
    Equal,
    Delete,
    Insert,
}

fn diff_ops(old: &[&str], new: &[&str]) -> Vec<(Op, String)> {
    let n = old.len();
    let m = new.len();
    // LCS 动态规划
    let mut dp = vec![vec![0u32; m + 1]; n + 1];
    for i in 0..n {
        for j in 0..m {
            if old[i] == new[j] {
                dp[i + 1][j + 1] = dp[i][j] + 1;
            } else {
                dp[i + 1][j + 1] = cmp::max(dp[i + 1][j], dp[i][j + 1]);
            }
        }
    }

    let mut ops = Vec::new();
    let mut i = n;
    let mut j = m;
    while i > 0 || j > 0 {
        if i > 0 && j > 0 && old[i - 1] == new[j - 1] {
            ops.push((Op::Equal, format!(" {}", old[i - 1])));
            i -= 1;
            j -= 1;
        } else if j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j]) {
            ops.push((Op::Insert, format!("+{}", new[j - 1])));
            j -= 1;
        } else if i > 0 {
            ops.push((Op::Delete, format!("-{}", old[i - 1])));
            i -= 1;
        }
    }
    ops.reverse();
    ops
}

struct Hunk {
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
    lines: Vec<String>,
}

fn group_hunks(ops: &[(Op, String)], context: usize) -> Vec<Hunk> {
    if ops.is_empty() {
        return Vec::new();
    }

    // 标记变更附近需要保留的上下文
    let mut keep = vec![false; ops.len()];
    for (idx, (op, _)) in ops.iter().enumerate() {
        if *op != Op::Equal {
            let start = idx.saturating_sub(context);
            let end = cmp::min(ops.len(), idx + context + 1);
            for slot in keep.iter_mut().take(end).skip(start) {
                *slot = true;
            }
        }
    }

    let mut hunks = Vec::new();
    let mut i = 0;
    let mut old_line = 1usize;
    let mut new_line = 1usize;

    while i < ops.len() {
        if !keep[i] {
            match ops[i].0 {
                Op::Equal => {
                    old_line += 1;
                    new_line += 1;
                }
                Op::Delete => old_line += 1,
                Op::Insert => new_line += 1,
            }
            i += 1;
            continue;
        }

        let hunk_old_start = old_line;
        let hunk_new_start = new_line;
        let mut old_count = 0usize;
        let mut new_count = 0usize;
        let mut lines = Vec::new();

        while i < ops.len() && keep[i] {
            let (op, text) = &ops[i];
            lines.push(text.clone());
            match op {
                Op::Equal => {
                    old_count += 1;
                    new_count += 1;
                    old_line += 1;
                    new_line += 1;
                }
                Op::Delete => {
                    old_count += 1;
                    old_line += 1;
                }
                Op::Insert => {
                    new_count += 1;
                    new_line += 1;
                }
            }
            i += 1;
        }

        hunks.push(Hunk {
            old_start: hunk_old_start,
            old_count,
            new_start: hunk_new_start,
            new_count,
            lines,
        });
    }

    hunks
}
