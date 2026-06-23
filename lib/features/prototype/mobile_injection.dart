import 'dart:convert';

import 'package:flutter/services.dart';

import '../../core/config/dunes_defaults.dart';
import '../../core/config/nova_config.dart';
import '../im/im_chat_injection.dart';
import '../im/kb_chat_injection.dart';
import '../im/nova_chat_injection.dart';
import '../nova/nova_api_injection.dart';

/// 注入 WebView 的 JS / CSS，将原型页转为全屏 App 模式并桥接导航。
abstract final class MobileInjection {
  static const css = r'''
.flutter-app-mode {
  padding: 0 !important;
  overflow: hidden !important;
  background: var(--bg-app) !important;
}
.flutter-app-mode .hero,
.flutter-app-mode .index,
.flutter-app-mode .foot,
.flutter-app-mode .deck-meta,
.flutter-app-mode .deck-nav,
.flutter-app-mode .fab {
  display: none !important;
}
.flutter-app-mode .deck {
  position: fixed !important;
  inset: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
  max-width: none !important;
  background: var(--bg-app) !important;
}
.flutter-app-mode .deck-stage {
  transform: none !important;
  height: 100% !important;
  margin: 0 !important;
  width: 100% !important;
}
.flutter-app-mode .phone {
  width: 100% !important;
  height: 100% !important;
  max-width: 100% !important;
  border-radius: 0 !important;
  padding: 0 !important;
  box-shadow: none !important;
  background: var(--bg-app) !important;
}
.flutter-app-mode .phone::before {
  display: none !important;
}
.flutter-app-mode .notch {
  display: none !important;
}
.flutter-app-mode .phone-screen {
  border-radius: 0 !important;
}
.flutter-app-mode .tab-bar {
  padding-bottom: 8px !important;
}
.flutter-app-mode .tab-bar::after,
.flutter-app-mode .home-indicator {
  display: none !important;
}
.flutter-app-mode .overlay {
  z-index: 200 !important;
}
.flutter-app-mode .screen[data-screen="C5"] .phone-screen,
.flutter-app-mode .screen[data-screen="C2"] .phone-screen {
  display: flex !important;
  flex-direction: column !important;
  height: 100% !important;
}
.flutter-app-mode .screen[data-screen="C4"] .phone-screen {
  display: flex !important;
  flex-direction: column !important;
  height: 100% !important;
}
.flutter-app-mode .screen[data-screen="C4"] .chat-conv-header,
.flutter-app-mode .screen[data-screen="C4"] #c4-model-picker-slot,
.flutter-app-mode .screen[data-screen="C4"] .c4-model-picker-wrap {
  flex-shrink: 0 !important;
}
.flutter-app-mode .screen[data-screen="C4"] .ai-prompts,
.flutter-app-mode .screen[data-screen="C4"] #c4-ai-prompts {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C4"] .ai-hero {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C4"] .content {
  flex: 1 !important;
  min-height: 0 !important;
  overflow: hidden !important;
  display: flex !important;
  flex-direction: column !important;
  padding: 0 !important;
}
.flutter-app-mode .screen[data-screen="C4"] .msg-stream {
  flex: 1 !important;
  overflow-y: auto !important;
  min-height: 0 !important;
  padding-bottom: 20px !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows {
  padding-bottom: 28px;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row:last-child {
  margin-bottom: 8px;
}
.flutter-app-mode .screen[data-screen="C4"] .msg-quick-actions,
.flutter-app-mode .screen[data-screen="C4"] .msg-input-bar {
  flex-shrink: 0 !important;
}
.flutter-app-mode .screen[data-screen="C4"] .c4-nova-draft-tray {
  flex-shrink: 0 !important;
  display: none;
  max-height: 120px;
  overflow: hidden;
}
.flutter-app-mode .screen[data-screen="C4"] .c4-nova-draft-tray.show {
  display: block !important;
}
.flutter-app-mode .screen[data-screen="C4"] .msg-quick-actions {
  display: grid !important;
  grid-template-columns: repeat(3, minmax(0, 1fr)) !important;
  width: 100% !important;
  gap: 0 !important;
  padding: 10px 0 8px !important;
  box-sizing: border-box !important;
  border-top: 1px solid var(--border-soft) !important;
  border-bottom: none !important;
}
.flutter-app-mode .screen[data-screen="C4"] .msg-quick-actions .qa-cell {
  width: 100% !important;
  min-width: 0 !important;
  padding-left: 0 !important;
  padding-right: 0 !important;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-input-busy-hint {
  flex-shrink: 0;
  padding: 6px 14px 0;
  font-size: 12px;
  line-height: 1.4;
  color: var(--text-3);
  text-align: center;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-input-busy-hint.nova-input-busy-flash {
  color: var(--coral);
}
.flutter-app-mode .screen[data-screen="C4"].nova-input-locked .msg-input-bar .input-box {
  background: var(--bg-soft);
}
.flutter-app-mode .screen[data-screen="C5"] .content,
.flutter-app-mode .screen[data-screen="C2"] .content {
  flex: 1 !important;
  min-height: 0 !important;
  display: flex !important;
  flex-direction: column !important;
}
.flutter-app-mode .screen[data-screen="C5"] .msg-stream,
.flutter-app-mode .screen[data-screen="C2"] .msg-stream {
  flex: 1 !important;
  overflow-y: auto !important;
  min-height: 0 !important;
}
.flutter-app-mode .screen[data-screen="C5"] .msg-quick-actions,
.flutter-app-mode .screen[data-screen="C2"] .msg-quick-actions {
  flex-shrink: 0 !important;
  display: grid !important;
  width: 100% !important;
  gap: 0 !important;
  padding: 10px 0 8px !important;
  box-sizing: border-box !important;
}
.flutter-app-mode .screen[data-screen="C5"] .msg-quick-actions {
  grid-template-columns: repeat(5, minmax(0, 1fr)) !important;
}
.flutter-app-mode .screen[data-screen="C2"] .msg-quick-actions {
  grid-template-columns: repeat(6, minmax(0, 1fr)) !important;
}
.flutter-app-mode .screen[data-screen="C5"] .msg-quick-actions .qa-cell,
.flutter-app-mode .screen[data-screen="C2"] .msg-quick-actions .qa-cell {
  width: 100% !important;
  min-width: 0 !important;
  padding-left: 0 !important;
  padding-right: 0 !important;
}
.flutter-app-mode .screen[data-screen="C5"] .msg-quick-actions .dunes-c5-at {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C5"] .msg-input-bar,
.flutter-app-mode .screen[data-screen="C2"] .msg-input-bar {
  flex-shrink: 0 !important;
}
.msg-read-status {
  font-family: var(--mono);
  font-size: 9px;
  margin-top: 3px;
  text-align: right;
  letter-spacing: .02em;
}
.msg-read-status.read { color: var(--text-3); }
.msg-read-status.unread { color: var(--accent); }
.flutter-app-mode .msg-date-divider {
  font-size: 11px;
  text-transform: none;
  letter-spacing: .04em;
  margin: 16px 0 10px;
  color: var(--text-2, #666);
}
.flutter-app-mode .screen[data-screen="C12"] .msg-date-divider {
  margin: 14px 4px 10px;
}
.flutter-app-mode .msg-row.sent .msg-content {
  align-items: flex-end !important;
}
.flutter-app-mode .msg-bubble.recv,
.flutter-app-mode .msg-bubble.sent {
  display: inline-block !important;
  width: fit-content !important;
  max-width: 100% !important;
  box-sizing: border-box !important;
}
.dunes-emoji-panel {
  display: none;
  padding: 8px 10px;
  background: var(--bg-app);
  border-top: 1px solid var(--border-soft);
  max-height: 140px;
  overflow-y: auto;
}
.dunes-emoji-grid {
  display: grid;
  grid-template-columns: repeat(8, 1fr);
  gap: 6px;
}
.dunes-emoji-btn {
  border: none;
  background: var(--bg-soft);
  border-radius: 8px;
  font-size: 22px;
  line-height: 1.2;
  padding: 6px 2px;
  cursor: pointer;
}
.dunes-emoji-btn:hover { background: var(--accent-soft); }
.dunes-emoji-btn img { display: block; margin: 0 auto; }
.flutter-app-mode .tab-bar .tab .red-dot {
  display: none !important;
  top: 0 !important;
  right: 14px !important;
  width: 9px !important;
  height: 9px !important;
  border-radius: 50% !important;
  border: 2px solid var(--bg-app) !important;
  background: var(--coral) !important;
  box-shadow: 0 0 0 1px rgba(200, 60, 60, 0.25);
}
.flutter-app-mode .tab-bar .tab .red-dot.show {
  display: block !important;
  animation: dunes-comm-dot-blink 1.1s ease-in-out infinite;
}
@keyframes dunes-comm-dot-blink {
  0%, 100% { opacity: 1; transform: scale(1); }
  50% { opacity: 0.2; transform: scale(0.82); }
}
.flutter-app-mode .chat-row .cr-av .av-dot { display: none; }
.flutter-app-mode .chat-row .cr-av .av-dot.on { display: block; }
.flutter-app-mode .contact-row .cr-av .av-dot { display: none; }
.flutter-app-mode .contact-row .cr-av .av-dot.on { display: block; }
.flutter-app-mode .profile-hero .ph-av .av-dot { display: none; }
.flutter-app-mode .profile-hero .ph-av .av-dot.on { display: block; }
.flutter-app-mode .chat-row .cr-av,
.flutter-app-mode .contact-row .cr-av,
.flutter-app-mode .cp-av,
.flutter-app-mode .cv-av-mini,
.flutter-app-mode .ph-av {
  position: relative;
  overflow: visible;
}
.flutter-app-mode .chat-row .cr-av .av-dot,
.flutter-app-mode .contact-row .cr-av .av-dot,
.flutter-app-mode .cp-av .av-dot,
.flutter-app-mode .cv-av-mini .av-dot,
.flutter-app-mode .ph-av .av-dot {
  position: absolute;
  bottom: -1px;
  right: -1px;
  z-index: 5;
  pointer-events: none;
  box-sizing: border-box;
}
.flutter-app-mode .chat-row .cr-av .av-dot {
  width: 11px;
  height: 11px;
  border-radius: 50%;
  background: #5D8A4E;
  border: 2px solid var(--bg-app);
}
.flutter-app-mode .contact-row .cr-av .av-dot,
.flutter-app-mode .cp-av .av-dot {
  width: 9px;
  height: 9px;
  border-radius: 50%;
  background: #22A47D;
  border: 1.5px solid var(--bg-app);
}
.flutter-app-mode .chat-conv-header.private .cv-av-mini { position: relative; overflow: visible; }
.flutter-app-mode .chat-conv-header.private .cv-av-mini .av-dot {
  position: absolute; bottom: -1px; right: -1px;
  width: 9px; height: 9px; border-radius: 50%;
  background: #22A47D; border: 2px solid var(--bg-app);
  display: none;
}
.flutter-app-mode .chat-conv-header.private .cv-av-mini .av-dot.on { display: block; }
.flutter-app-mode .screen[data-screen="C2"] .phone-screen,
.flutter-app-mode .screen[data-screen="C5"] .phone-screen {
  position: relative;
}
.flutter-app-mode .dunes-chat-overlays {
  position: absolute;
  left: 0;
  right: 0;
  bottom: 58px;
  z-index: 12;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  pointer-events: none;
}
.flutter-app-mode .dunes-chat-overlays > * {
  pointer-events: auto;
}
.flutter-app-mode .dunes-jump-latest {
  position: static;
  bottom: auto;
  z-index: 6;
  display: flex;
  justify-content: center;
  padding: 0;
  pointer-events: none;
}
.flutter-app-mode .dunes-jump-latest button {
  pointer-events: auto;
  font-size: 11px;
  padding: 6px 14px;
  border-radius: 16px;
  border: 1px solid var(--accent-line);
  background: var(--bg-app);
  color: var(--accent-deep);
  box-shadow: 0 4px 14px rgba(31, 36, 33, 0.12);
  cursor: pointer;
}
.flutter-app-mode .msg-stream {
  position: relative;
}
.flutter-app-mode .dunes-new-msgs-float {
  position: static;
  bottom: auto;
  z-index: 7;
  display: none;
  margin: 0;
  width: fit-content;
  padding: 8px 14px;
  border: none;
  border-radius: 999px;
  background: linear-gradient(135deg, #7E64BD 0%, #553B96 100%);
  color: #fff;
  font-size: 12px;
  box-shadow: 0 4px 12px rgba(85, 59, 150, 0.35);
  cursor: pointer;
}
.flutter-app-mode .msg-system.dunes-msg-focus,
.flutter-app-mode .msg-row.dunes-msg-focus {
  animation: dunes-msg-flash 2.4s ease;
}
@keyframes dunes-msg-flash {
  0%, 100% { background: transparent; }
  20%, 60% { background: rgba(124, 98, 194, 0.14); border-radius: 8px; }
}
.flutter-app-mode .msg-row.sent .msg-bubble.sent.msg-bubble--media {
  background: transparent !important;
  border: none !important;
  box-shadow: none !important;
  padding: 0 !important;
}
.flutter-app-mode .msg-row.sent .msg-bubble.sent.msg-bubble--media .dunes-attach-link {
  color: var(--accent-deep, #553B96);
}
.flutter-app-mode #c1-conv-list:not(.dunes-api-ready) > * { display: none !important; }
.flutter-app-mode #c1-conv-list.dunes-api-ready:empty::before {
  content: '加载会话…';
  display: block;
  padding: 24px 16px;
  color: var(--text-3);
  font-size: 12px;
}
.flutter-app-mode .c1-swipe-item {
  position: relative;
  overflow: hidden;
  background: var(--bg-app);
}
.flutter-app-mode .c1-swipe-item + .c1-swipe-item::before,
.flutter-app-mode .c1-swipe-item + .chat-row::before,
.flutter-app-mode .chat-row + .c1-swipe-item::before {
  content: '';
  position: absolute;
  left: 72px;
  right: 0;
  top: 0;
  height: 1px;
  background: var(--border-soft);
  pointer-events: none;
}
.flutter-app-mode .c1-swipe-actions {
  position: absolute;
  right: 0;
  top: 0;
  bottom: 0;
  width: 72px;
  display: flex;
  align-items: stretch;
  justify-content: center;
  background: #E5484D;
}
.flutter-app-mode .c1-swipe-delete {
  flex: 1;
  border: 0;
  background: transparent;
  color: #fff;
  font-size: 14px;
  font-weight: 600;
  letter-spacing: 0.02em;
  cursor: pointer;
}
.flutter-app-mode .c1-swipe-content {
  position: relative;
  z-index: 1;
  background: var(--bg-app);
  transition: transform 0.22s ease;
  will-change: transform;
}
.flutter-app-mode .c1-swipe-item.open .c1-swipe-content {
  transform: translateX(-72px);
}
.flutter-app-mode .c1-swipe-item .chat-row::before {
  display: none !important;
}
.flutter-app-mode .c1-swipe-item .chat-row {
  background: var(--bg-app);
}
.flutter-app-mode .chat-row .cr-bd .cr-pv .generating {
  color: var(--accent-deep);
  font-weight: 500;
}
.flutter-app-mode .chat-row .cr-bd .cr-pv .generating .ti-spin {
  display: inline-block;
  animation: spin 1s linear infinite;
  font-size: 11px;
  margin-right: 2px;
  vertical-align: -1px;
}
.flutter-app-mode .nova-icon-img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: contain;
  border-radius: inherit;
  pointer-events: none;
}
.flutter-app-mode .chat-row .cr-av.ai-bot {
  background: transparent !important;
  box-shadow: none !important;
  padding: 0 !important;
  overflow: hidden;
}
.flutter-app-mode .chat-row .cr-av.ai-bot .nova-icon-img { border-radius: 12px; }
.flutter-app-mode .msg-row .msg-av-sm.ai-bot {
  background: transparent !important;
  box-shadow: none !important;
  padding: 0 !important;
  overflow: hidden;
}
.flutter-app-mode .msg-row .msg-av-sm.ai-bot .nova-icon-img { border-radius: 9px; }
.flutter-app-mode .ai-hero .ah-av {
  background: transparent !important;
  box-shadow: none !important;
  padding: 0 !important;
  overflow: hidden;
}
.flutter-app-mode .ai-hero .ah-av .nova-icon-img { border-radius: 14px; }
.flutter-app-mode .noti-card .nc-ic.nova-hist-ic {
  background: transparent !important;
  padding: 0 !important;
  overflow: hidden;
}
.flutter-app-mode .chat-section .chat-section-nova-ic {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 15px;
  height: 15px;
  margin-right: 5px;
  vertical-align: -2px;
}
.flutter-app-mode .chat-section .nova-ic-sm {
  width: 15px;
  height: 15px;
}
.flutter-app-mode .chat-row .cr-bd .cr-nm .kb-mark {
  font-family: var(--mono);
  font-size: 8.5px;
  font-weight: 700;
  background: linear-gradient(135deg, #2F5D62, #5F8B8F);
  color: #fff;
  padding: 1px 5px;
  border-radius: 3px;
  letter-spacing: .04em;
  line-height: 1.5;
  flex-shrink: 0;
}
.flutter-app-mode .chat-row .cr-av.kb-chat {
  background: linear-gradient(145deg, #1B3A3F 0%, #2F5D62 52%, #5F8B8F 100%) !important;
  color: #fff;
  box-shadow: 0 4px 12px -3px rgba(27, 58, 63, .38), inset 0 1px 0 rgba(255, 255, 255, .14);
  position: relative;
  overflow: hidden;
}
.flutter-app-mode .chat-row .cr-av.kb-chat::after {
  content: '';
  position: absolute;
  top: -14px;
  right: -14px;
  width: 34px;
  height: 34px;
  border-radius: 50%;
  background: radial-gradient(circle, rgba(255, 213, 128, .28), transparent 68%);
  pointer-events: none;
}
.flutter-app-mode .chat-row .cr-av.kb-chat .kb-chat-ic {
  width: 22px;
  height: 22px;
  display: block;
  position: relative;
  z-index: 1;
}
.flutter-app-mode .qj-cell .qj-ic .nova-icon-img {
  width: 28px;
  height: 28px;
  margin: 0 auto;
}
.flutter-app-mode .screen[data-screen="C5"] .msg-stream > :not(#c5-api-rows),
.flutter-app-mode .screen[data-screen="C2"] .msg-stream > :not(#c2-api-rows) {
  display: none !important;
}
.flutter-app-mode #c7-mock-contacts,
.flutter-app-mode .screen[data-screen="C7"] .content > .chat-section,
.flutter-app-mode .screen[data-screen="C3"] .dept-tree > :not(.dept-block) {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C7"] .new-conv-kinds .nck.nck-disabled {
  display: none !important;
}
.flutter-app-mode .dept-head .dh-select-all {
  margin-left: 8px;
  padding: 2px 8px;
  border: 1px solid var(--accent-line);
  border-radius: 6px;
  background: var(--accent-soft);
  color: var(--accent-deep);
  font-size: 10px;
  font-weight: 600;
  cursor: pointer;
  flex-shrink: 0;
}
.flutter-app-mode .c7-bulk-bar {
  display: flex;
  gap: 8px;
  padding: 6px 12px 4px;
  align-items: center;
}
.flutter-app-mode .c7-bulk-bar button {
  padding: 4px 10px;
  border-radius: 6px;
  border: 1px solid var(--border-soft);
  background: var(--bg-soft);
  font-size: 10px;
  font-weight: 600;
  color: var(--text-2);
  cursor: pointer;
}
.flutter-app-mode .screen[data-screen="C7"] .content > .contact-pick-row,
.flutter-app-mode .screen[data-screen="C7"] .selected-stack .ss-tag {
  display: none !important;
}
.flutter-app-mode .dept-block { margin-bottom: 6px; }
.flutter-app-mode .dept-block .dept-block {
  margin-left: 14px;
  padding-left: 8px;
  border-left: 2px solid var(--border-soft);
}
.flutter-app-mode .dept-people { margin: 0 0 8px 4px; }
.flutter-app-mode .dept-people .contact-row,
.flutter-app-mode .dept-people .contact-pick-row { margin-bottom: 4px; }
.flutter-app-mode .contact-row.contact-disabled .ct-nm { color: var(--text-3); }
.flutter-app-mode .screen[data-screen="C7"] .cp-av .av-dot { display: none !important; }
.flutter-app-mode #dunes-member-picker-list .cp-av .av-dot { display: none !important; }
.flutter-app-mode .screen[data-screen="C9"] .c9-mock { display: none !important; }
.flutter-app-mode .screen[data-screen="C9"] .profile-hero .ph-tags { display: none !important; }
.flutter-app-mode .screen[data-screen="C9"] .profile-hero .ph-av .av-dot { display: none !important; }
.flutter-app-mode .screen[data-screen="C9"] .profile-hero .ph-more { display: none !important; }
.flutter-app-mode .screen[data-screen="C9"] #c9-dynamic-body { display: block !important; }
.flutter-app-mode #c7-contact-list.dept-tree { padding: 0 10px 12px; }
.flutter-app-mode #z2-noti-list:not(.z2-api-ready) > *:not(#z2-api-rows) { display: none !important; }
.flutter-app-mode #z2-noti-list.z2-api-ready > *:not(#z2-api-rows) { display: none !important; }
.flutter-app-mode .screen[data-screen="C10"] .content > :not(#c10-api-rows),
.flutter-app-mode .screen[data-screen="C11"] .content > :not(#c11-api-rows),
.flutter-app-mode .screen[data-screen="C13"] .content > :not(#c13-api-rows) {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C11"] .ds-crumb,
.flutter-app-mode .screen[data-screen="C11"] .ds-name .id,
.flutter-app-mode .screen[data-screen="C11"] .action-bar,
.flutter-app-mode .screen[data-screen="C11"] .dunes-c11-mock {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C11"] .ds-name {
  font-size: 17px !important;
  font-weight: 600;
}
.flutter-app-mode .screen[data-screen="C11"] #c11-search-bar.dunes-c11-search-on {
  display: flex !important;
}
.flutter-app-mode .screen[data-screen="C12"] .content > :not(.gsearch-bar):not(#c12-api-rows) {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C12"] .ds-crumb,
.flutter-app-mode .screen[data-screen="C12"] .ds-name .id,
.flutter-app-mode .screen[data-screen="C12"] .ds-more,
.flutter-app-mode .screen[data-screen="C10"] .ds-more,
.flutter-app-mode .screen[data-screen="Z2"] .ds-more,
.flutter-app-mode .screen[data-screen="C12"] .action-bar {
  display: none !important;
}
.flutter-app-mode .noti-card.noti-card-static { cursor: default; }
.flutter-app-mode .noti-card .nc-desc,
.flutter-app-mode .chat-row.broadcast .cr-pv,
.flutter-app-mode .chat-row.system .cr-pv {
  white-space: pre-wrap;
  word-break: break-word;
}
/* 云枢列表预览单行省略 */
.flutter-app-mode #c1-conv-list .chat-row .cr-av.ai-bot + .cr-bd .cr-pv {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  line-height: 1.4;
  max-width: 100%;
}
.flutter-app-mode #c1-conv-list .chat-row .cr-av.ai-bot + .cr-bd .cr-pv .generating {
  display: inline-block;
  max-width: 100%;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  vertical-align: bottom;
}
.flutter-app-mode .screen[data-screen="C12"] .ds-name {
  font-size: 17px !important;
}
.flutter-app-mode .dunes-msg-focus .msg-bubble,
.flutter-app-mode .dunes-msg-focus .pill {
  outline: 2px solid var(--accent);
  box-shadow: 0 0 0 4px rgba(47, 93, 98, 0.16);
}
.flutter-app-mode .screen[data-screen="C3"] .content {
  overflow-anchor: none;
}
.flutter-app-mode .msg-input-bar.voice-mode .input-box {
  display: none !important;
}
.flutter-app-mode .msg-input-bar .voice-hold-btn {
  display: none;
  flex: 1;
  min-width: 0;
  height: 38px;
  align-items: center;
  justify-content: center;
  background: var(--bg-soft);
  border-radius: 8px;
  font-size: 15px;
  font-weight: 600;
  color: var(--text);
  user-select: none;
  touch-action: none;
  cursor: pointer;
  letter-spacing: 0.02em;
}
.flutter-app-mode .msg-input-bar.voice-mode .voice-hold-btn {
  display: flex;
}
.flutter-app-mode .msg-input-bar .voice-hold-btn.active {
  background: #d4d4d4;
}
.flutter-app-mode .dunes-voice-record-overlay {
  position: absolute;
  inset: 0;
  z-index: 120;
  display: none;
  align-items: flex-end;
  justify-content: center;
  padding-bottom: calc(env(safe-area-inset-bottom, 0px) + 112px);
  background: rgba(0, 0, 0, 0.42);
  pointer-events: none;
}
.flutter-app-mode .dunes-voice-record-overlay.show {
  display: flex;
}
.flutter-app-mode .dunes-voice-record-panel {
  min-width: 168px;
  padding: 18px 28px 16px;
  border-radius: 12px;
  background: rgba(70, 70, 70, 0.94);
  color: #fff;
  text-align: center;
  box-shadow: 0 8px 28px rgba(0, 0, 0, 0.28);
}
.flutter-app-mode .dunes-voice-record-overlay.cancel .dunes-voice-record-panel {
  background: rgba(185, 52, 52, 0.94);
}
.flutter-app-mode .dunes-voice-record-waves {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 4px;
  height: 32px;
  margin-bottom: 10px;
}
.flutter-app-mode .dunes-voice-record-waves span {
  width: 4px;
  height: 12px;
  border-radius: 2px;
  background: #fff;
  animation: dunesVoiceBar 0.75s ease-in-out infinite;
}
.flutter-app-mode .dunes-voice-record-waves span:nth-child(1) { animation-delay: 0s; }
.flutter-app-mode .dunes-voice-record-waves span:nth-child(2) { animation-delay: 0.12s; }
.flutter-app-mode .dunes-voice-record-waves span:nth-child(3) { animation-delay: 0.24s; }
.flutter-app-mode .dunes-voice-record-waves span:nth-child(4) { animation-delay: 0.12s; }
.flutter-app-mode .dunes-voice-record-waves span:nth-child(5) { animation-delay: 0s; }
.flutter-app-mode .dunes-voice-record-tip {
  font-size: 14px;
  font-weight: 500;
  letter-spacing: 0.01em;
}
@keyframes dunesVoiceBar {
  0%, 100% { height: 10px; opacity: 0.55; }
  50% { height: 26px; opacity: 1; }
}
.flutter-app-mode .dunes-voice-bubble {
  min-width: 86px;
  max-width: 190px;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  user-select: none;
}
.flutter-app-mode .screen[data-screen="K2"] .dunes-kb-voice-row .dunes-voice-bubble {
  min-width: 92px;
  padding: 10px 14px;
}
.flutter-app-mode .screen[data-screen="K2"] .dunes-kb-voice-row .dunes-voice-bubble .voice-sec,
.flutter-app-mode .screen[data-screen="K2"] .dunes-kb-voice-row .dunes-voice-bubble .voice-wave {
  color: #fff;
}
.flutter-app-mode .screen[data-screen="K2"] .kb-voice-transcript {
  max-width: 240px;
  text-align: right;
}
.flutter-app-mode .dunes-voice-bubble .voice-wave {
  display: inline-flex;
  width: 18px;
  height: 18px;
  align-items: center;
  justify-content: center;
}
.flutter-app-mode .dunes-voice-bubble .voice-sec {
  font-weight: 600;
  font-size: 13px;
}
.flutter-app-mode .dunes-voice-bubble.playing .voice-wave {
  animation: dunesVoicePulse 0.8s ease-in-out infinite;
}
.flutter-app-mode .dunes-attach-link {
  color: inherit;
  text-decoration: none;
  font-weight: 600;
}
.flutter-app-mode .dunes-img-thumb {
  max-width: 170px;
  max-height: 170px;
  border-radius: 10px;
  display: block;
  cursor: pointer;
  object-fit: cover;
}
.flutter-app-mode .dunes-upload-bubble {
  position: relative;
  min-width: 120px;
}
.flutter-app-mode .dunes-upload-preview {
  opacity: 0.78;
}
.flutter-app-mode .dunes-upload-file {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  max-width: 220px;
  word-break: break-all;
}
.flutter-app-mode .dunes-upload-progress {
  margin-top: 8px;
  height: 4px;
  border-radius: 99px;
  background: rgba(0, 0, 0, 0.08);
  overflow: hidden;
}
.flutter-app-mode .msg-bubble.sent .dunes-upload-progress {
  background: rgba(255, 255, 255, 0.28);
}
.flutter-app-mode .dunes-upload-progress-bar {
  height: 100%;
  width: 0;
  border-radius: inherit;
  background: linear-gradient(90deg, #7E64BD, #553B96);
  transition: width 0.18s ease;
}
.flutter-app-mode .dunes-upload-label {
  margin-top: 6px;
  font-size: 11px;
  color: var(--text-3, #888);
  text-align: center;
}
.flutter-app-mode .msg-bubble.sent .dunes-upload-label {
  color: rgba(255, 255, 255, 0.82);
}
@keyframes dunesVoicePulse {
  0%, 100% { opacity: .45; transform: scale(.92); }
  50% { opacity: 1; transform: scale(1.08); }
}
.flutter-app-mode .dunes-image-viewer {
  position: fixed;
  inset: 0;
  background: rgba(5, 5, 5, 0.92);
  z-index: 9999;
  display: none;
  align-items: center;
  justify-content: center;
}
.flutter-app-mode .dunes-image-viewer.show { display: flex; }
.flutter-app-mode .dunes-image-viewer .dunes-image-stage {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  touch-action: none;
}
.flutter-app-mode .dunes-image-viewer .dunes-image-full {
  max-width: 96vw;
  max-height: 88vh;
  transform-origin: center center;
  transition: transform 0.06s linear;
  will-change: transform;
  user-select: none;
  -webkit-user-drag: none;
}
.flutter-app-mode .dunes-image-viewer .dunes-image-close {
  position: absolute;
  top: 16px;
  right: 16px;
  width: 36px;
  height: 36px;
  border-radius: 999px;
  border: 1px solid rgba(255,255,255,0.28);
  background: rgba(255,255,255,0.12);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  cursor: pointer;
  z-index: 2;
}
.flutter-app-mode .dunes-image-viewer .dunes-image-download {
  position: absolute;
  top: 16px;
  right: 60px;
  width: 36px;
  height: 36px;
  border-radius: 999px;
  border: 1px solid rgba(255,255,255,0.28);
  background: rgba(255,255,255,0.12);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  cursor: pointer;
  z-index: 2;
}
.flutter-app-mode .screen[data-screen="C2"] .chat-pinned-ctx {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C13"] .tab-tog,
.flutter-app-mode .screen[data-screen="C13"] .section-label,
.flutter-app-mode .screen[data-screen="C13"] .api-strip,
.flutter-app-mode .screen[data-screen="C13"] .ds-name .id {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C13"] #c13-api-rows .upload-slot {
  cursor: pointer;
}
.flutter-app-mode .screen[data-screen="C13"] #c13-api-rows .c13-thumb {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  object-fit: cover;
  flex-shrink: 0;
}
.flutter-app-mode #dunes-dialog-root {
  display: none;
  position: fixed;
  inset: 0;
  z-index: 220;
  background: rgba(0,0,0,.42);
  align-items: center;
  justify-content: center;
  padding: 20px;
}
.flutter-app-mode #dunes-dialog-root.show {
  display: flex;
}
.flutter-app-mode .dunes-dialog-card {
  width: 100%;
  max-width: 320px;
  background: var(--bg-app, #fff);
  border-radius: 14px;
  box-shadow: 0 12px 40px rgba(0,0,0,.18);
  overflow: hidden;
}
.flutter-app-mode .dunes-dialog-body {
  padding: 20px 18px 16px;
  font-size: 14px;
  line-height: 1.5;
  color: var(--text-1, #111);
  text-align: center;
}
.flutter-app-mode .dunes-dialog-input {
  width: 100%;
  margin-top: 12px;
  padding: 10px 12px;
  border: 1px solid var(--border-soft, #e8e8e8);
  border-radius: 10px;
  font-size: 14px;
  box-sizing: border-box;
}
.flutter-app-mode .dunes-dialog-actions {
  display: flex;
  border-top: 1px solid var(--border-soft, #eee);
}
.flutter-app-mode .dunes-dialog-actions button {
  flex: 1;
  padding: 14px 10px;
  border: none;
  background: transparent;
  font-size: 15px;
  cursor: pointer;
}
.flutter-app-mode .dunes-dialog-actions button.cancel {
  color: var(--text-2, #666);
  border-right: 1px solid var(--border-soft, #eee);
}
.flutter-app-mode .dunes-dialog-actions button.ok {
  color: var(--accent, #2f5d62);
  font-weight: 700;
}
.flutter-app-mode .profile-head .avatar {
  cursor: pointer;
}
.flutter-app-mode .profile-head .avatar.has-img {
  background: transparent;
  color: transparent;
  overflow: hidden;
}
.flutter-app-mode .profile-head .avatar.has-img img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}
.flutter-app-mode .profile-head .badges {
  display: none !important;
}
.flutter-app-mode .dunes-ptr-indicator {
  position: absolute;
  left: 0;
  right: 0;
  top: 0;
  height: 0;
  overflow: hidden;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  z-index: 30;
  pointer-events: none;
  transition: height .18s ease;
}
.flutter-app-mode .dunes-ptr-indicator .dunes-ptr-inner {
  padding: 8px 0 10px;
  font-size: 11px;
  color: var(--text-3, #888);
  display: flex;
  align-items: center;
  gap: 6px;
}
.flutter-app-mode .dunes-ptr-indicator.pulling .dunes-ptr-inner,
.flutter-app-mode .dunes-ptr-indicator.refreshing .dunes-ptr-inner {
  color: var(--accent, #7e64bd);
}
.flutter-app-mode .screen .content.dunes-ptr-pulling {
  transition: transform .12s ease;
}
.flutter-app-mode .cr-av.has-img,
.flutter-app-mode .cp-av.has-img,
.flutter-app-mode .cv-av-mini.has-img,
.flutter-app-mode .ph-av.has-img {
  background: transparent;
  color: transparent;
  overflow: visible;
  position: relative;
}
.flutter-app-mode .cr-av.has-img img,
.flutter-app-mode .cp-av.has-img img,
.flutter-app-mode .cv-av-mini.has-img img,
.flutter-app-mode .ph-av.has-img img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: inherit;
}
.flutter-app-mode .msg-row .msg-av-sm.has-img {
  background: transparent;
  color: transparent;
  overflow: hidden;
}
.flutter-app-mode .msg-row .msg-av-sm.has-img img {
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: 50%;
}
.flutter-app-mode .b2-logout-wrap {
  padding: 20px 0 28px;
  margin-top: 8px;
}
.flutter-app-mode .b2-logout-btn {
  width: 100%;
  border: 1px solid rgba(200, 60, 60, 0.28);
  background: rgba(200, 60, 60, 0.08);
  color: var(--coral);
  border-radius: 12px;
  padding: 12px;
  font-family: var(--sans);
  font-size: 14px;
  font-weight: 600;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 6px;
  cursor: pointer;
}
.flutter-app-mode #dunes-avatar-sheet-root {
  display: none;
  position: fixed;
  inset: 0;
  z-index: 230;
  background: rgba(0,0,0,.42);
  align-items: flex-end;
  justify-content: center;
}
.flutter-app-mode #dunes-avatar-sheet-root.show {
  display: flex;
}
.flutter-app-mode .dunes-avatar-sheet {
  width: 100%;
  max-width: 480px;
  background: var(--bg-app, #fff);
  border-radius: 18px 18px 0 0;
  padding: 16px 16px calc(16px + env(safe-area-inset-bottom, 0px));
  box-shadow: 0 -8px 32px rgba(0,0,0,.12);
  max-height: 78vh;
  overflow: auto;
}
.flutter-app-mode .dunes-avatar-sheet h3 {
  margin: 0 0 4px;
  font-size: 16px;
  font-weight: 600;
  text-align: center;
}
.flutter-app-mode .dunes-avatar-sheet .hint {
  margin: 0 0 14px;
  font-size: 12px;
  color: var(--text-2, #666);
  text-align: center;
}
.flutter-app-mode .dunes-avatar-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
  margin-bottom: 14px;
}
.flutter-app-mode .dunes-avatar-pick {
  aspect-ratio: 1;
  border-radius: 50%;
  border: 2px solid transparent;
  padding: 0;
  background: var(--bg-soft, #f5f5f5);
  cursor: pointer;
  overflow: hidden;
}
.flutter-app-mode .dunes-avatar-pick.selected {
  border-color: var(--accent, #7E64BD);
  box-shadow: 0 0 0 3px rgba(126,100,189,.18);
}
.flutter-app-mode .dunes-avatar-pick img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.flutter-app-mode .dunes-avatar-upload-btn {
  width: 100%;
  border: 1px dashed var(--border-soft, #ddd);
  background: var(--bg-soft, #fafafa);
  border-radius: 12px;
  padding: 12px;
  font-size: 14px;
  color: var(--accent, #7E64BD);
  cursor: pointer;
  margin-bottom: 12px;
}
.flutter-app-mode .dunes-avatar-sheet-actions {
  display: flex;
  gap: 10px;
}
.flutter-app-mode .dunes-avatar-sheet-actions button {
  flex: 1;
  border: none;
  border-radius: 12px;
  padding: 12px;
  font-size: 15px;
  cursor: pointer;
}
.flutter-app-mode .dunes-avatar-sheet-actions .cancel {
  background: var(--bg-soft, #f2f2f2);
  color: var(--text-2, #666);
}
.flutter-app-mode .dunes-avatar-sheet-actions .ok {
  background: var(--accent, #7E64BD);
  color: #fff;
  font-weight: 600;
}
.flutter-app-mode .screen[data-screen="C4"] .chat-conv-header .cv-sub,
.flutter-app-mode .screen[data-screen="C4"] .ai-hero .ah-sub {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C4"] .ai-prompts .ap-h {
  cursor: pointer;
  justify-content: space-between;
}
/* C4 推荐对话：App 内默认折叠，点标题加 .expanded 才展开 */
.flutter-app-mode .screen[data-screen="C4"] .ai-prompts .ai-prompts-grid {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C4"] .ai-prompts.expanded .ai-prompts-grid {
  display: grid !important;
}
.flutter-app-mode .screen[data-screen="C4"] .ai-prompts .ap-chev {
  font-size: 14px;
  color: var(--text-3);
  transition: transform .2s ease;
}
.flutter-app-mode .screen[data-screen="C4"] .ai-prompts.expanded .ap-chev {
  transform: rotate(180deg);
}
.flutter-app-mode .screen[data-screen="C4"] .ai-prompts.expanded .ap-h {
  margin-bottom: 7px;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-msg-stream > .msg-system.dunes-nova-pinned {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-msg-stream > .msg-row,
.flutter-app-mode .screen[data-screen="C4"] #c4-msg-stream > .msg-system.flow {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row {
  display: flex !important;
  align-items: flex-start !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row .msg-content {
  align-items: flex-start !important;
  gap: 4px !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.sent .msg-content {
  align-items: flex-end !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-meta {
  padding: 0 2px !important;
  min-height: 14px !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-bubble.ai-recv::before {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv {
  flex-direction: row !important;
  align-items: flex-start !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .msg-content {
  align-items: flex-start !important;
  max-width: 82% !important;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .msg-bubble {
  width: 100%;
  box-sizing: border-box;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-text,
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-tools-wrap,
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-panel {
  width: 100%;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-panel {
  margin-bottom: 8px;
  border-radius: 10px;
  background: var(--bg-soft);
  border: 1px solid var(--border-soft);
  overflow: hidden;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-toggle {
  display: flex;
  align-items: flex-start;
  flex-wrap: wrap;
  gap: 4px 6px;
  padding: 8px 10px;
  cursor: pointer;
  user-select: none;
  font-size: 11.5px;
  color: var(--text-2);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-toggle .nova-think-ic {
  font-size: 13px;
  color: var(--accent-deep);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-toggle .nova-think-label {
  font-weight: 600;
  color: var(--text-1);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-toggle .nova-think-status {
  flex: 1 1 100%;
  min-width: 0;
  font-size: 11px;
  color: var(--text-3);
  white-space: normal;
  overflow: visible;
  text-overflow: unset;
  line-height: 1.4;
  word-break: break-word;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-toggle .nova-think-chev {
  font-size: 12px;
  color: var(--text-3);
  transition: transform 0.2s;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-panel.collapsed .nova-think-chev {
  transform: rotate(-90deg);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-panel.collapsed .nova-think-body-wrap {
  display: none;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-body-wrap {
  padding: 0 10px 8px;
  border-top: 1px solid var(--border-soft);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-think-body {
  margin-top: 6px;
  font-size: 11px;
  line-height: 1.55;
  color: var(--text-3);
  white-space: pre-wrap;
  word-break: break-word;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-tool-steps {
  margin-top: 6px;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-tool-step {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 10.5px;
  color: var(--text-3);
  font-family: var(--mono);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-tool-step.done {
  color: var(--green);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-tool-step.pending {
  color: var(--accent-deep);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.recv .nova-tool-step .ti-spin {
  animation: spin 1s linear infinite;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-row.dunes-nova-turn-focus .msg-bubble {
  outline: 2px solid rgba(47, 93, 98, 0.35);
  box-shadow: 0 0 0 3px rgba(47, 93, 98, 0.12);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-date-divider,
.flutter-app-mode .screen[data-screen="C11"] #c11-api-rows .msg-date-divider {
  display: flex; justify-content: center; margin: 10px 0 6px;
  font-size: 11px; color: var(--text-3);
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-read-status {
  font-size: 10px;
  margin-top: 2px;
  text-align: right;
  width: 100%;
}
.flutter-app-mode .screen[data-screen="C4"] #c4-api-rows .msg-meta .badge-ai {
  font-family: var(--mono);
  font-size: 7.5px;
  background: linear-gradient(135deg, #FFD580, #FFA850);
  color: #5D3508;
  padding: 1px 5px;
  border-radius: 3px;
  font-weight: 700;
  letter-spacing: 0.06em;
  line-height: 1.5;
  text-transform: uppercase;
  vertical-align: 1px;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-file-card {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-top: 8px;
  padding: 10px 12px;
  background: var(--bg-soft);
  border: 1px solid var(--border);
  border-radius: 12px;
  cursor: pointer;
  max-width: 100%;
  text-align: left;
  transition: background 0.15s, border-color 0.15s;
  box-shadow: 0 1px 4px rgba(15, 23, 42, 0.04);
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-file-card:active {
  background: var(--accent-soft);
  border-color: var(--accent-line);
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-file-card .dnf-icon {
  flex-shrink: 0;
  width: 40px;
  height: 40px;
  border-radius: 10px;
  background: #fff;
  border: 1px solid var(--border);
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--accent-deep);
  font-size: 22px;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-file-card .dnf-bd {
  flex: 1;
  min-width: 0;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-file-card .dnf-name {
  font-size: 14px;
  font-weight: 600;
  color: var(--text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-file-card .dnf-meta {
  font-size: 11px;
  color: var(--text-3);
  margin-top: 2px;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-file-card .dnf-go {
  flex-shrink: 0;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: var(--bg-soft);
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--accent-deep);
  font-size: 16px;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-image-card {
  display: block;
  margin-top: 8px;
  max-width: min(280px, 100%);
  border-radius: 12px;
  overflow: hidden;
  border: 1px solid var(--border);
  background: var(--bg-soft);
  cursor: pointer;
  text-align: left;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-image-card:active {
  opacity: 0.92;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-img-preview {
  display: block;
  width: 100%;
  max-height: 220px;
  object-fit: contain;
  background: #f4f4f6;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-image-card .dni-foot {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 10px;
  border-top: 1px solid var(--border);
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-image-card .dni-name {
  flex: 1;
  min-width: 0;
  font-size: 13px;
  font-weight: 600;
  color: var(--text);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-image-card .dni-hint {
  flex-shrink: 0;
  font-size: 11px;
  color: var(--text-3);
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-image-card .dni-actions {
  display: flex;
  align-items: center;
  gap: 4px;
  flex-shrink: 0;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-image-card .dni-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border: none;
  border-radius: 8px;
  background: var(--bg-soft);
  color: var(--text-2);
  cursor: pointer;
  transition: background 0.15s, color 0.15s;
}
.flutter-app-mode .screen[data-screen="C4"] .dunes-nova-image-card .dni-btn:active {
  background: var(--accent-soft);
  color: var(--accent-deep);
}
.flutter-app-mode .screen[data-screen="C4"] .msg-bubble.ai-recv .nova-text,
.flutter-app-mode .screen[data-screen="C4"] .msg-bubble.ai-recv {
  line-height: 1.65;
  word-break: break-word;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-inline-code {
  font-family: var(--mono, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace);
  font-size: 0.88em;
  padding: 0.15em 0.45em;
  border-radius: 6px;
  background: rgba(47, 93, 98, 0.08);
  color: var(--accent-deep);
  border: 1px solid rgba(47, 93, 98, 0.12);
}
.flutter-app-mode .screen[data-screen="C4"] .nova-md-link {
  color: var(--accent-deep);
  text-decoration: underline;
  text-underline-offset: 2px;
  word-break: break-all;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-md-link:active {
  opacity: 0.75;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-md-h {
  font-size: 15px;
  font-weight: 700;
  color: var(--text);
  margin: 10px 0 6px;
  line-height: 1.45;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-md-p {
  margin: 4px 0;
  line-height: 1.65;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-md-list {
  margin: 6px 0 8px;
  padding-left: 18px;
  list-style: disc;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-md-list li {
  margin: 4px 0;
  line-height: 1.6;
}
.flutter-app-mode .screen[data-screen="C4"] .chat-conv-header .ic-btn.nova-header-disabled {
  opacity: 0.38;
  pointer-events: none;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-code-block {
  margin: 10px 0;
  border-radius: 12px;
  overflow: hidden;
  border: 1px solid rgba(15, 23, 42, 0.12);
  background: #1e1e2e;
  box-shadow: 0 4px 16px rgba(15, 23, 42, 0.08);
  max-width: 100%;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-code-block.is-streaming {
  border-color: rgba(47, 93, 98, 0.35);
}
.flutter-app-mode .screen[data-screen="C4"] .nova-code-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 8px 12px;
  background: rgba(255, 255, 255, 0.04);
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
}
.flutter-app-mode .screen[data-screen="C4"] .nova-code-lang {
  font-family: var(--mono, ui-monospace, monospace);
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: rgba(255, 255, 255, 0.55);
}
.flutter-app-mode .screen[data-screen="C4"] .nova-code-copy {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 4px 10px;
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.06);
  color: rgba(255, 255, 255, 0.85);
  font-size: 11px;
  cursor: pointer;
  transition: background 0.15s;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-code-copy:active {
  background: rgba(255, 255, 255, 0.14);
}
.flutter-app-mode .screen[data-screen="C4"] .nova-code-pre {
  margin: 0;
  padding: 14px 16px;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-code-body {
  font-family: var(--mono, ui-monospace, SFMono-Regular, Menlo, Consolas, monospace);
  font-size: 13px;
  line-height: 1.55;
  color: #e2e8f0;
  white-space: pre;
  tab-size: 2;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-code-stream-hint {
  padding: 6px 12px 10px;
  font-size: 11px;
  color: rgba(255, 255, 255, 0.45);
  border-top: 1px solid rgba(255, 255, 255, 0.06);
}
.flutter-app-mode .screen[data-screen="C4"] .nova-tool-chip.pending {
  opacity: 0.85;
}
.flutter-app-mode .screen[data-screen="C4"] .nova-tool-chip .ti-spin {
  animation: spin 1s linear infinite;
}
@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}
/* 敬请期待 · 模糊遮罩（千机 / 我的薪资等未开放板块） */
.flutter-app-mode .coming-soon-wrap {
  position: relative;
  isolation: isolate;
}
.flutter-app-mode .coming-soon-wrap > .coming-soon-mask {
  position: absolute;
  inset: 0;
  z-index: 12;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(251, 250, 246, 0.55);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  border-radius: 12px;
  pointer-events: auto;
  cursor: default;
}
.flutter-app-mode .coming-soon-wrap > .coming-soon-mask .soon-label {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 3px;
  font-family: var(--serif);
  font-size: 11px;
  font-weight: 600;
  color: var(--accent-deep);
  letter-spacing: 0.1em;
  padding: 9px 18px;
  background: rgba(255, 255, 255, 0.92);
  border: 1px solid var(--accent-line);
  border-radius: 999px;
  box-shadow: 0 6px 24px -6px rgba(85, 59, 150, 0.25);
  line-height: 1.2;
  text-align: center;
}
.flutter-app-mode .coming-soon-wrap > .coming-soon-mask .soon-block {
  font-size: 9px;
  font-weight: 500;
  letter-spacing: 0.06em;
  opacity: 0.72;
  text-transform: none;
}
.flutter-app-mode .b2-soon-disabled {
  cursor: default !important;
}
.flutter-app-mode .b2-soon-disabled .arr {
  opacity: 0.35;
}
.flutter-app-mode .screen[data-screen="LH"] .app-bar.has-back > .ds-back,
.flutter-app-mode .screen[data-screen="B2"] .app-bar.has-back > .ds-back {
  display: none !important;
}
.flutter-app-mode .screen[data-screen="LH"] .app-bar.has-back,
.flutter-app-mode .screen[data-screen="B2"] .app-bar.has-back {
  gap: 0;
}
.flutter-app-mode .screen[data-screen="C6"] .gi-row.c6-flow-push-hidden {
  display: none !important;
}
.flutter-app-mode #c6-clear-history {
  display: none !important;
}
.flutter-app-mode .coming-soon-wrap > .coming-soon-mask .soon-main {
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.12em;
}
.flutter-app-mode .screen[data-screen="QJ"] .content.coming-soon-wrap {
  min-height: 58vh;
}
.flutter-app-mode .coming-soon-wrap.dunes-soon-block {
  margin-bottom: 10px;
}
/* 统一页面 loading 遮罩：数据就绪前隐藏内容区 */
.flutter-app-mode .screen.dunes-screen-loading .content,
.flutter-app-mode .screen.dunes-screen-loading .msg-stream {
  visibility: hidden !important;
  pointer-events: none !important;
}
.flutter-app-mode .phone-screen {
  position: relative;
}
.flutter-app-mode .dunes-screen-loading-mask {
  position: absolute;
  inset: 0;
  z-index: 90;
  display: none;
  align-items: center;
  justify-content: center;
  background: var(--bg-app, #fbfaf6);
}
.flutter-app-mode .screen.dunes-screen-loading .dunes-screen-loading-mask {
  display: flex;
}
.flutter-app-mode .dunes-screen-loading-inner {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  color: var(--text-3, #8a8178);
  font-size: 12px;
}
.flutter-app-mode .dunes-screen-loading-spin {
  width: 28px;
  height: 28px;
  border: 2.5px solid rgba(85, 59, 150, 0.15);
  border-top-color: var(--accent, #553B96);
  border-radius: 50%;
  animation: spin 0.75s linear infinite;
}
''';

  static const _profileJs = r'''
var PRESET_AVATARS = [
  { id: 'cartoon-01', src: 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#FFE8A3"/><circle cx="60" cy="58" r="38" fill="#FFD36B"/><circle cx="44" cy="54" r="5" fill="#4A3580"/><circle cx="76" cy="54" r="5" fill="#4A3580"/><path d="M42 72 Q60 86 78 72" stroke="#4A3580" stroke-width="4" fill="none" stroke-linecap="round"/></svg>') },
  { id: 'cartoon-02', src: 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#D8F5FF"/><circle cx="60" cy="58" r="38" fill="#7EC8E3"/><ellipse cx="44" cy="56" rx="6" ry="8" fill="#2D4A6E"/><ellipse cx="76" cy="56" rx="6" ry="8" fill="#2D4A6E"/><path d="M48 76 Q60 68 72 76" stroke="#2D4A6E" stroke-width="3.5" fill="none" stroke-linecap="round"/></svg>') },
  { id: 'cartoon-03', src: 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#F3E8FF"/><circle cx="60" cy="58" r="38" fill="#B58AE8"/><circle cx="44" cy="54" r="5" fill="#3B2870"/><circle cx="76" cy="54" r="5" fill="#3B2870"/><path d="M46 74 Q60 84 74 74" stroke="#3B2870" stroke-width="4" fill="none" stroke-linecap="round"/></svg>') },
  { id: 'cartoon-04', src: 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#E8FFF0"/><circle cx="60" cy="58" r="38" fill="#6BCB9A"/><rect x="38" y="50" width="12" height="4" rx="2" fill="#1F4D3A"/><rect x="70" y="50" width="12" height="4" rx="2" fill="#1F4D3A"/><path d="M44 74 Q60 80 76 74" stroke="#1F4D3A" stroke-width="4" fill="none" stroke-linecap="round"/></svg>') },
  { id: 'cartoon-05', src: 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#FFE4EC"/><circle cx="60" cy="58" r="38" fill="#FF8FAB"/><circle cx="44" cy="54" r="5" fill="#6B1E3C"/><circle cx="76" cy="54" r="5" fill="#6B1E3C"/><path d="M42 70 Q60 88 78 70" stroke="#6B1E3C" stroke-width="4" fill="none" stroke-linecap="round"/></svg>') },
  { id: 'cartoon-06', src: 'data:image/svg+xml,' + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 120 120"><rect width="120" height="120" rx="60" fill="#FFF0D6"/><circle cx="60" cy="58" r="38" fill="#F4A261"/><circle cx="44" cy="52" r="6" fill="#5D3508"/><circle cx="76" cy="52" r="6" fill="#5D3508"/><path d="M46 76 Q60 70 74 76" stroke="#5D3508" stroke-width="4" fill="none" stroke-linecap="round"/></svg>') }
];
function maskPhone(p) {
  if (!p || p.length < 7) return p || '';
  return p.slice(0, 3) + '****' + p.slice(-4);
}
function presetAvatarSrc(presetId) {
  var found = PRESET_AVATARS.find(function (a) { return a.id === presetId; });
  return found ? found.src : '';
}
async function resolveAvatarUrl(profile) {
  if (!profile) return '';
  if (profile.avatarPreset) return presetAvatarSrc(profile.avatarPreset);
  if (!profile.avatarObjectKey) return '';
  var base = localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
  var token = localStorage.getItem('dunes_token') || '';
  try {
    var r = await fetch(base + '/storage/presigned-get?bucket=user-avatars&objectKey=' + encodeURIComponent(profile.avatarObjectKey), {
      headers: token ? { Authorization: 'Bearer ' + token } : {}
    });
    if (!r.ok) return '';
    var j = await r.json();
    return (j.data && j.data.url) || '';
  } catch (e) { return ''; }
}
function renderProfileAvatar(el, profile) {
  if (!el) return;
  var name = (profile && profile.displayName) || '';
  var initial = name ? name.charAt(0) : '';
  el.classList.remove('has-img');
  el.innerHTML = '';
  el.textContent = initial;
  if (!profile) return;
  var srcPromise;
  if (profile.avatarPreset) {
    srcPromise = Promise.resolve(presetAvatarSrc(profile.avatarPreset));
  } else if (profile.avatarObjectKey) {
    srcPromise = resolveAvatarUrl(profile);
  } else {
    return;
  }
  srcPromise.then(function (src) {
    if (!src || !el.isConnected) return;
    el.classList.add('has-img');
    el.textContent = '';
    var img = document.createElement('img');
    img.alt = name || '头像';
    img.src = src;
    el.appendChild(img);
  });
}
window.__dunesUserProfiles = window.__dunesUserProfiles || {};
function rememberUserProfile(c) {
  if (!c) return;
  var uid = Number(c.userId || c.peerUserId || c.id);
  if (!uid) return;
  var prev = window.__dunesUserProfiles[String(uid)] || {};
  window.__dunesUserProfiles[String(uid)] = {
    userId: uid,
    displayName: c.displayName || c.peerDisplayName || prev.displayName || '',
    avatarPreset: c.avatarPreset || c.peerAvatarPreset || prev.avatarPreset || '',
    avatarObjectKey: c.avatarObjectKey || c.peerAvatarObjectKey || prev.avatarObjectKey || ''
  };
}
function rememberDeptProfiles(dep) {
  (dep.users || []).forEach(rememberUserProfile);
  (dep.children || []).forEach(rememberDeptProfiles);
}
function profileForUserId(uid) {
  return window.__dunesUserProfiles[String(uid)] || null;
}
function devUserIdFromStorage() {
  var uid = parseInt(localStorage.getItem('dunes_user_id') || '0', 10);
  return isNaN(uid) ? 0 : uid;
}
function personClassForUser(uid) {
  var n = Math.abs(Number(uid) || 0) % 6;
  return 'person-' + ['a', 'b', 'c', 'd', 'e', 'f'][n];
}
function refreshAvatarDotForEl(el, uid) {
  if (!el) return;
  var dot = el.querySelector('.av-dot');
  if (!dot) return;
  uid = Number(uid || el.getAttribute('data-avatar-user-id') || 0);
  var online = window.__dunesOnlineUserIds || {};
  var on = uid > 0 && !!online[String(uid)];
  if (window.DunesPresence && typeof window.DunesPresence.isUserOnline === 'function' && uid > 0) {
    on = window.DunesPresence.isUserOnline(uid);
  }
  dot.classList.toggle('on', on);
}
function myMsgAvatarHtml(initial) {
  var uid = devUserIdFromStorage();
  var letter = String(initial || '?').slice(0, 1);
  return '<div class="msg-av-sm ' + personClassForUser(uid) + '" data-avatar-user-id="' + uid + '">' + letter + '</div>';
}
function applyMyMsgAvatar(row, initial) {
  if (!row) return;
  var av = row.querySelector('.msg-av-sm[data-avatar-user-id]:not(.ai-bot):not(.kb-ai-av)');
  if (!av || typeof renderListAvatar !== 'function') return;
  var uid = devUserIdFromStorage();
  var p = profileForUserId(uid) || (window.__dunesCurrentProfile ? Object.assign({ userId: uid }, window.__dunesCurrentProfile) : null);
  if (p) renderListAvatar(av, p, initial || (p.displayName || '?').slice(0, 1));
}
function hydrateMsgAvatarsIn(root) {
  if (!root || typeof renderListAvatar !== 'function') return;
  root.querySelectorAll('.msg-av-sm[data-avatar-user-id]:not(.ai-bot):not(.kb-ai-av)').forEach(function (el) {
    if (el.classList.contains('has-img')) return;
    var uid = Number(el.getAttribute('data-avatar-user-id'));
    if (!uid) return;
    var p = profileForUserId(uid);
    if (!p && uid === devUserIdFromStorage() && window.__dunesCurrentProfile) {
      p = Object.assign({ userId: uid }, window.__dunesCurrentProfile);
    }
    if (!p || (!p.avatarPreset && !p.avatarObjectKey)) return;
    renderListAvatar(el, p, (p.displayName || el.textContent || '?').slice(0, 1));
  });
}
function renderListAvatar(el, profile, initial) {
  if (!el) return;
  var dot = el.querySelector('.av-dot');
  var hadOn = dot && dot.classList.contains('on');
  var letter = initial || (profile && profile.displayName ? profile.displayName.charAt(0) : '?');
  el.classList.remove('has-img');
  el.textContent = letter;
  var dotEl = document.createElement('div');
  dotEl.className = 'av-dot' + (hadOn ? ' on' : '');
  el.appendChild(dotEl);
  refreshAvatarDotForEl(el, profile && (profile.userId || profile.id));
  if (!profile) return;
  var srcPromise;
  if (profile.avatarPreset) {
    srcPromise = Promise.resolve(presetAvatarSrc(profile.avatarPreset));
  } else if (profile.avatarObjectKey) {
    srcPromise = resolveAvatarUrl(profile);
  } else {
    return;
  }
  srcPromise.then(function (src) {
    if (!src || !el.isConnected) return;
    var keepOn = el.querySelector('.av-dot');
    hadOn = keepOn && keepOn.classList.contains('on');
    el.classList.add('has-img');
    el.textContent = '';
    var img = document.createElement('img');
    img.alt = profile.displayName || '头像';
    img.src = src;
    el.appendChild(img);
    dotEl = document.createElement('div');
    dotEl.className = 'av-dot' + (hadOn ? ' on' : '');
    el.appendChild(dotEl);
    refreshAvatarDotForEl(el, profile && (profile.userId || profile.id));
  });
}
function hydrateAvatarsIn(root) {
  if (!root) return;
  root.querySelectorAll('[data-avatar-user-id]').forEach(function (el) {
    var uid = Number(el.getAttribute('data-avatar-user-id'));
    if (!uid) return;
    var p = profileForUserId(uid);
    if (p) renderListAvatar(el, p, el.classList.contains('no-initial') ? ' ' : (p.displayName || '?').slice(0, 1));
  });
}
window.DunesAvatars = {
  rememberUserProfile: rememberUserProfile,
  rememberDeptProfiles: rememberDeptProfiles,
  profileForUserId: profileForUserId,
  renderListAvatar: renderListAvatar,
  hydrateAvatarsIn: hydrateAvatarsIn,
  myMsgAvatarHtml: myMsgAvatarHtml,
  applyMyMsgAvatar: applyMyMsgAvatar,
  hydrateMsgAvatarsIn: hydrateMsgAvatarsIn,
  refreshAvatarDotForEl: refreshAvatarDotForEl
};
function applyUserProfile(p) {
  p = p || {};
  var screen = document.querySelector('.screen[data-screen="B2"]');
  if (!screen) return;
  var avatar = screen.querySelector('.profile-head .avatar');
  var nm = screen.querySelector('.profile-head .nm');
  var rl = screen.querySelector('.profile-head .rl');
  var badges = screen.querySelector('.profile-head .badges');
  var protoName = '王一凡';
  var protoRole = '市场部 · 能源版块';
  var name = String(p.displayName || localStorage.getItem('dunes_display_name') || '').trim();
  if (!name) {
    var phone = String(p.phone || localStorage.getItem('dunes_phone') || '').trim();
    if (phone) name = phone;
  }
  if (!name) {
    var uid = localStorage.getItem('dunes_user_id') || '';
    if (uid) name = '用户' + uid;
  }
  renderProfileAvatar(avatar, p);
  if (nm) {
    if (name) nm.textContent = name;
    else if ((nm.textContent || '').trim() === protoName) nm.textContent = '—';
  }
  if (rl) {
    var parts = [];
    if (p.departmentName) parts.push(p.departmentName);
    if (p.title) parts.push(p.title);
    if (p.phone) parts.push(String(p.phone));
    var line = parts.filter(Boolean).join(' · ');
    if (line) rl.textContent = line;
    else if ((rl.textContent || '').trim() === protoRole) rl.textContent = '';
    else rl.textContent = '';
  }
  if (badges) {
    badges.innerHTML = '';
    badges.style.display = 'none';
  }
}
function readCachedProfile() {
  try {
    var roles = [];
    try { roles = JSON.parse(localStorage.getItem('dunes_roles') || '[]'); } catch (e) {}
    var uid = parseInt(localStorage.getItem('dunes_user_id') || '', 10);
    return {
      id: isNaN(uid) ? null : uid,
      displayName: localStorage.getItem('dunes_display_name') || '',
      phone: localStorage.getItem('dunes_phone') || '',
      roles: roles
    };
  } catch (e) { return null; }
}
function notifyFlutterLogout() {
  try {
    if (window.DunesFlutterChannel) {
      window.DunesFlutterChannel.postMessage(JSON.stringify({ type: 'logout' }));
      return;
    }
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ source: 'dunes-prototype', type: 'logout' }, '*');
    }
  } catch (e) {}
}
function clearAuthStorage() {
  var keys = [
    'dunes_token',
    'dunes_jwt',
    'dunes_user_id',
    'dunes_display_name',
    'dunes_phone',
    'dunes_roles'
  ];
  keys.forEach(function (k) {
    try { localStorage.removeItem(k); } catch (e) {}
  });
}
function handleSessionRevoked() {
  clearAuthStorage();
  notifyFlutterLogout();
  if (window.DunesDialog && typeof window.DunesDialog.alert === 'function') {
    window.DunesDialog.alert('账号已在其他设备登录，请重新登录');
  }
}
window.__dunesHandleSessionRevoked = handleSessionRevoked;
window.__dunesWireHoldToTalkVoice = function (opts) {
  opts = opts || {};
  var screen = opts.screen;
  var prefix = String(opts.prefix || 'voice');
  var inputBar = screen && screen.querySelector('.msg-input-bar');
  var voiceBtn = inputBar && inputBar.querySelector('.voice-btn');
  var textInput = opts.textInput || document.getElementById(prefix + '-input');
  if (!voiceBtn || !inputBar || !textInput || voiceBtn.dataset.dunesHoldWired) return;
  voiceBtn.dataset.dunesHoldWired = '1';
  voiceBtn.title = '切换语音';
  var holdBtn = document.createElement('div');
  holdBtn.className = 'voice-hold-btn';
  holdBtn.textContent = '按住 说话';
  holdBtn.setAttribute('role', 'button');
  holdBtn.setAttribute('aria-label', '按住说话');
  textInput.insertAdjacentElement('afterend', holdBtn);
  var phoneScreen = screen.querySelector('.phone-screen');
  var overlayId = 'dunes-voice-overlay-' + prefix;
  var overlay = document.getElementById(overlayId);
  if (!overlay && phoneScreen) {
    overlay = document.createElement('div');
    overlay.id = overlayId;
    overlay.className = 'dunes-voice-record-overlay';
    overlay.innerHTML = '<div class="dunes-voice-record-panel">'
      + '<div class="dunes-voice-record-waves"><span></span><span></span><span></span><span></span><span></span></div>'
      + '<div class="dunes-voice-record-tip">松开 发送</div></div>';
    phoneScreen.appendChild(overlay);
  }
  var overlayTip = overlay ? overlay.querySelector('.dunes-voice-record-tip') : null;
  var voiceMode = false;
  var isHolding = false;
  var willCancel = false;
  var abortRecording = false;
  var sendOnStop = true;
  var activeRec = null;
  var activeStream = null;
  var activeChunks = [];
  var startedAt = 0;
  var stopTimer = 0;
  var holdPointerId = null;
  var holdStartY = 0;
  var CANCEL_THRESHOLD = 72;
  function canRecord() {
    if (typeof opts.canRecord === 'function') return !!opts.canRecord();
    return true;
  }
  function showToast(msg) {
    if (typeof opts.showToast === 'function') opts.showToast(screen, msg);
    else if (typeof alert === 'function') alert(msg);
  }
  function setVoiceMode(on) {
    voiceMode = !!on;
    inputBar.classList.toggle('voice-mode', voiceMode);
    voiceBtn.innerHTML = voiceMode
      ? '<i class="ti ti-keyboard"></i>'
      : '<i class="ti ti-microphone"></i>';
    voiceBtn.title = voiceMode ? '切换键盘' : '切换语音';
    if (voiceMode && textInput) textInput.blur();
  }
  function showVoiceOverlay(cancel) {
    if (!overlay) return;
    overlay.classList.add('show');
    overlay.classList.toggle('cancel', !!cancel);
    if (overlayTip) overlayTip.textContent = cancel ? '松开手指，取消发送' : '松开 发送';
  }
  function hideVoiceOverlay() {
    if (!overlay) return;
    overlay.classList.remove('show', 'cancel');
    if (overlayTip) overlayTip.textContent = '松开 发送';
  }
  function cleanupVoiceStream() {
    if (stopTimer) { clearTimeout(stopTimer); stopTimer = 0; }
    if (activeStream) activeStream.getTracks().forEach(function (t) { try { t.stop(); } catch (_) {} });
    activeStream = null;
  }
  function resetVoiceState() {
    cleanupVoiceStream();
    activeRec = null;
    activeChunks = [];
    isHolding = false;
    willCancel = false;
    abortRecording = false;
    sendOnStop = true;
    holdPointerId = null;
    holdBtn.classList.remove('active');
    hideVoiceOverlay();
  }
  voiceBtn.addEventListener('click', function (e) {
    e.preventDefault();
    if (isHolding || (activeRec && activeRec.state === 'recording')) return;
    setVoiceMode(!voiceMode);
  });
  holdBtn.addEventListener('pointerdown', async function (e) {
    if (e.pointerType === 'mouse' && e.button !== 0) return;
    e.preventDefault();
    if (!canRecord()) {
      if (typeof opts.onBlocked === 'function') opts.onBlocked();
      return;
    }
    if (isHolding || (activeRec && activeRec.state === 'recording')) return;
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia || typeof MediaRecorder === 'undefined') {
      showToast('当前环境不支持语音录制');
      return;
    }
    try {
      if (typeof opts.beforeRecord === 'function') await opts.beforeRecord();
    } catch (err) {
      showToast((err && err.message) || '无法开始录音');
      return;
    }
    if (!canRecord()) {
      if (typeof opts.onBlocked === 'function') opts.onBlocked();
      return;
    }
    isHolding = true;
    willCancel = false;
    abortRecording = false;
    sendOnStop = true;
    holdPointerId = e.pointerId;
    holdStartY = e.clientY;
    holdBtn.classList.add('active');
    showVoiceOverlay(false);
    try { holdBtn.setPointerCapture(e.pointerId); } catch (_) {}
    try {
      activeStream = await navigator.mediaDevices.getUserMedia({ audio: true });
      if (!isHolding || abortRecording) { resetVoiceState(); return; }
      activeChunks = [];
      activeRec = new MediaRecorder(activeStream);
      startedAt = Date.now();
      activeRec.ondataavailable = function (ev) {
        if (ev.data && ev.data.size > 0) activeChunks.push(ev.data);
      };
      activeRec.onstop = async function () {
        var shouldSend = sendOnStop && !abortRecording;
        var sec = Math.max(0, Math.round((Date.now() - startedAt) / 1000));
        var recMime = activeRec && activeRec.mimeType ? activeRec.mimeType : 'audio/webm';
        var blob = new Blob(activeChunks, { type: recMime });
        cleanupVoiceStream();
        activeRec = null;
        activeChunks = [];
        holdBtn.classList.remove('active');
        hideVoiceOverlay();
        if (!shouldSend) return;
        if (sec < 1) { showToast('说话时间太短'); return; }
        if (!blob.size) { showToast('录音内容为空，请重试'); return; }
        if (typeof opts.onVoiceBlob !== 'function') return;
        try { await opts.onVoiceBlob(blob, recMime, Math.max(1, sec)); }
        catch (err) { showToast('语音处理失败：' + ((err && err.message) || err)); }
      };
      activeRec.start();
      stopTimer = setTimeout(function () {
        if (activeRec && activeRec.state === 'recording') {
          try { activeRec.stop(); } catch (_) {}
        }
      }, 30000);
      if (!isHolding) {
        try { if (activeRec.state === 'recording') activeRec.stop(); } catch (_) {}
      }
    } catch (err) {
      resetVoiceState();
      showToast('语音录制失败：' + ((err && err.message) || err));
    }
  });
  function finishHoldRecord() {
    if (!isHolding) return;
    isHolding = false;
    sendOnStop = !willCancel;
    hideVoiceOverlay();
    holdBtn.classList.remove('active');
    if (activeRec && activeRec.state === 'recording') {
      try { activeRec.stop(); } catch (_) {}
      return;
    }
    if (!activeRec) abortRecording = true;
    cleanupVoiceStream();
  }
  holdBtn.addEventListener('pointermove', function (e) {
    if (!isHolding || e.pointerId !== holdPointerId) return;
    willCancel = e.clientY < holdStartY - CANCEL_THRESHOLD;
    showVoiceOverlay(willCancel);
  });
  holdBtn.addEventListener('pointerup', function (e) {
    if (e.pointerId !== holdPointerId) return;
    e.preventDefault();
    finishHoldRecord();
  });
  holdBtn.addEventListener('pointercancel', function (e) {
    if (e.pointerId !== holdPointerId) return;
    willCancel = true;
    finishHoldRecord();
  });
};
function wireLogoutButton() {
  var screen = document.querySelector('.screen[data-screen="B2"]');
  if (!screen) return;
  var content = screen.querySelector('.content');
  if (!content) return;
  if (content.querySelector('.b2-logout-wrap')) return;
  var wrap = document.createElement('div');
  wrap.className = 'b2-logout-wrap';
  wrap.innerHTML = '<button type="button" class="b2-logout-btn"><i class="ti ti-logout"></i>退出登录</button>';
  content.appendChild(wrap);
  var btn = wrap.querySelector('.b2-logout-btn');
  if (!btn) return;
  btn.addEventListener('click', function () {
    clearAuthStorage();
    notifyFlutterLogout();
  });
}
function ensureAvatarSheet() {
  var root = document.getElementById('dunes-avatar-sheet-root');
  if (root) return root;
  root = document.createElement('div');
  root.id = 'dunes-avatar-sheet-root';
  root.innerHTML = '<div class="dunes-avatar-sheet" role="dialog" aria-modal="true">'
    + '<h3>编辑头像</h3><p class="hint">选择卡通头像或上传自定义图片</p>'
    + '<div class="dunes-avatar-grid" id="dunes-avatar-grid"></div>'
    + '<button type="button" class="dunes-avatar-upload-btn" id="dunes-avatar-upload-btn"><i class="ti ti-upload"></i> 上传图片</button>'
    + '<input type="file" id="dunes-avatar-file" accept="image/*" style="position:fixed;left:-9999px;opacity:0;width:1px;height:1px">'
    + '<div class="dunes-avatar-sheet-actions">'
    + '<button type="button" class="cancel" id="dunes-avatar-cancel">取消</button>'
    + '<button type="button" class="ok" id="dunes-avatar-save">保存</button>'
    + '</div></div>';
  document.body.appendChild(root);
  root.addEventListener('click', function (e) {
    if (e.target === root) closeAvatarSheet();
  });
  root.querySelector('#dunes-avatar-cancel').addEventListener('click', closeAvatarSheet);
  return root;
}
var avatarSheetState = { preset: '', objectKey: '', previewSrc: '' };
function closeAvatarSheet() {
  var root = document.getElementById('dunes-avatar-sheet-root');
  if (root) root.classList.remove('show');
}
function openAvatarSheet(profile) {
  var root = ensureAvatarSheet();
  var grid = root.querySelector('#dunes-avatar-grid');
  avatarSheetState = {
    preset: (profile && profile.avatarPreset) || '',
    objectKey: (profile && profile.avatarObjectKey) || '',
    previewSrc: ''
  };
  grid.innerHTML = PRESET_AVATARS.map(function (a) {
    var sel = avatarSheetState.preset === a.id ? ' selected' : '';
    return '<button type="button" class="dunes-avatar-pick' + sel + '" data-preset="' + a.id + '"><img src="' + a.src + '" alt="' + a.id + '"></button>';
  }).join('');
  grid.querySelectorAll('.dunes-avatar-pick').forEach(function (btn) {
    btn.addEventListener('click', function () {
      grid.querySelectorAll('.dunes-avatar-pick').forEach(function (b) { b.classList.remove('selected'); });
      btn.classList.add('selected');
      avatarSheetState.preset = btn.getAttribute('data-preset') || '';
      avatarSheetState.objectKey = '';
      avatarSheetState.previewSrc = '';
    });
  });
  root.classList.add('show');
}
async function uploadAvatarFile(file) {
  var base = localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
  var token = localStorage.getItem('dunes_token') || '';
  var form = new FormData();
  form.append('file', file, file.name || ('avatar-' + Date.now() + '.jpg'));
  form.append('bucket', 'user-avatars');
  var r = await fetch(base + '/storage/upload', {
    method: 'POST',
    headers: token ? { Authorization: 'Bearer ' + token } : {},
    body: form
  });
  var j = await r.json();
  if (!r.ok || !j.success || !j.data || !j.data.objectKey) {
    throw new Error((j && j.message) || '上传失败');
  }
  return j.data.objectKey;
}
async function saveAvatarSelection() {
  var base = localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
  var token = localStorage.getItem('dunes_token') || '';
  if (!token) throw new Error('未登录');
  var body = {};
  if (avatarSheetState.objectKey) body.avatarObjectKey = avatarSheetState.objectKey;
  else if (avatarSheetState.preset) body.avatarPreset = avatarSheetState.preset;
  else throw new Error('请选择头像或上传图片');
  var r = await fetch(base + '/users/me', {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + token },
    body: JSON.stringify(body)
  });
  var text = await r.text();
  var j = {};
  try { j = JSON.parse(text); } catch (e) {}
  if (!r.ok || !j.success) {
    throw new Error((j && j.message) || text || ('HTTP ' + r.status));
  }
  return j.data || j;
}
function wireAvatarEditor() {
  var screen = document.querySelector('.screen[data-screen="B2"]');
  if (!screen || screen.dataset.avatarWired) return;
  screen.dataset.avatarWired = '1';
  var avatar = screen.querySelector('.profile-head .avatar');
  if (!avatar) return;
  avatar.setAttribute('role', 'button');
  avatar.setAttribute('aria-label', '编辑头像');
  avatar.title = '点击编辑头像';
  avatar.addEventListener('click', function () {
    openAvatarSheet(window.__dunesCurrentProfile || readCachedProfile());
  });
  var root = ensureAvatarSheet();
  if (root.dataset.actionsWired) return;
  root.dataset.actionsWired = '1';
  var fileInput = root.querySelector('#dunes-avatar-file');
  var uploadBtn = root.querySelector('#dunes-avatar-upload-btn');
  uploadBtn.addEventListener('click', function () { fileInput.click(); });
  fileInput.addEventListener('change', async function () {
    var f = fileInput.files && fileInput.files[0];
    fileInput.value = '';
    if (!f) return;
    try {
      uploadBtn.disabled = true;
      uploadBtn.textContent = '上传中…';
      var key = await uploadAvatarFile(f);
      avatarSheetState.objectKey = key;
      avatarSheetState.preset = '';
      avatarSheetState.previewSrc = URL.createObjectURL(f);
      var grid = root.querySelector('#dunes-avatar-grid');
      grid.querySelectorAll('.dunes-avatar-pick').forEach(function (b) { b.classList.remove('selected'); });
    } catch (err) {
      alert('上传失败：' + ((err && err.message) || err));
    } finally {
      uploadBtn.disabled = false;
      uploadBtn.innerHTML = '<i class="ti ti-upload"></i> 上传图片';
    }
  });
  root.querySelector('#dunes-avatar-save').addEventListener('click', async function () {
    var saveBtn = root.querySelector('#dunes-avatar-save');
    try {
      saveBtn.disabled = true;
      saveBtn.textContent = '保存中…';
      var updated = await saveAvatarSelection();
      window.__dunesCurrentProfile = updated;
      applyUserProfile(updated);
      closeAvatarSheet();
    } catch (err) {
      alert('保存失败：' + ((err && err.message) || err));
    } finally {
      saveBtn.disabled = false;
      saveBtn.textContent = '保存';
    }
  });
}
async function refreshUserProfile() {
  wireLogoutButton();
  wireAvatarEditor();
  var cached = readCachedProfile();
  window.__dunesCurrentProfile = cached;
  applyUserProfile(cached);
  var base = localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
  var token = localStorage.getItem('dunes_token') || '';
  if (!token) return;
  try {
    var r = await fetch(base + '/users/me', { headers: { Authorization: 'Bearer ' + token } });
    if (!r.ok) return;
    var j = await r.json();
    var d = j.data || j;
    if (d) {
      window.__dunesCurrentProfile = d;
      applyUserProfile(d);
      rememberUserProfile(Object.assign({ userId: d.id || d.userId }, d));
    }
  } catch (e) {}
}
window.__dunesRefreshUserProfile = refreshUserProfile;

function wireNovaC4() {
  var YUNSHU_NAME = '云枢';
  var YUNSHU_INTRO = '你好，我是你的云枢助手';
  var YUNSHU_HEAD = YUNSHU_NAME + ' <span class="group-tag" style="background:linear-gradient(135deg,#FFD580,#FFA850);color:#5D3508">AI</span>';
  var screen = document.querySelector('.screen[data-screen="C4"]');
  if (!screen) return;
  screen.dataset.name = YUNSHU_NAME;
  document.querySelectorAll('.screen[data-screen="C4"] .cv-nm').forEach(function (el) {
    el.innerHTML = YUNSHU_HEAD;
  });
  document.querySelectorAll('.screen[data-screen="C4"] .ah-nm').forEach(function (el) {
    el.innerHTML = YUNSHU_NAME + '<span class="badge-ai">AI</span>';
  });
  document.querySelectorAll('.screen[data-screen="C4"] .msg-meta .nm').forEach(function (el) {
    if (el.textContent.indexOf('沙丘助手') >= 0 || el.textContent.indexOf('NOVA') >= 0 || el.textContent.indexOf(YUNSHU_NAME) >= 0) el.textContent = YUNSHU_NAME;
  });
  var prompts = document.getElementById('c4-ai-prompts') || screen.querySelector('.ai-prompts');
  if (prompts) prompts.style.display = 'none';
  document.querySelectorAll('.screen[data-screen="C4"] .ah-av').forEach(function (el) {
    if (window.dunesNovaIconHtml) el.innerHTML = window.dunesNovaIconHtml();
  });
  if (typeof window.patchNovaIcons === 'function') window.patchNovaIcons();
  window.__dunesNovaIntro = YUNSHU_INTRO;
}
window.__dunesWireNovaC4 = wireNovaC4;
''';

  /// 通讯录：从 im-go `/contacts` 拉真数据渲染 C3/C7（由 Flutter 注入，不依赖根目录 index.html）。
  static const _contactsJs = r'''
window.DunesContacts = (function () {
  var debounceTimer = null;
  var c3Loaded = false;
  var c3LastQuery = '';
  function c3ContentEl() {
    return document.querySelector('.screen[data-screen="C3"] .content');
  }
  function rememberC3Scroll() {
    var c = c3ContentEl();
    if (!c) return;
    window.__dunesC3ScrollTop = c.scrollTop;
  }
  function restoreC3Scroll() {
    var c = c3ContentEl();
    if (!c) return;
    var top = Number(window.__dunesC3ScrollTop || 0);
    setTimeout(function () { c.scrollTop = top; }, 0);
  }
  function devUserId() {
    var uid = parseInt(localStorage.getItem('dunes_user_id') || '7', 10);
    return isNaN(uid) ? 7 : uid;
  }
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/"/g, '&quot;');
  }
  function isContactDisabled(c) {
    return !!(c && c.enabled === false);
  }
  function contactDisplayName(c) {
    var name = (c && c.displayName) || '';
    if (isContactDisabled(c)) name += '-停用';
    return name;
  }
  function contactMetaHtml(c) {
    var role = c.title || (c.roleCodes && c.roleCodes[0]) || '';
    var dept = c.department || '';
    var html = '';
    if (role) html += '<span class="role">' + esc(role) + '</span>';
    if (dept) html += '<span>' + esc(dept) + '</span>';
    return html;
  }
  function updateC7OrgLabel(total) {
    var list = document.getElementById('c7-contact-list');
    if (!list) return;
    var wrap = document.getElementById('c7-org-label');
    if (!wrap) {
      wrap = document.createElement('div');
      wrap.id = 'c7-org-label';
      wrap.className = 'section-label';
      wrap.style.margin = '8px 14px 4px';
      list.parentNode.insertBefore(wrap, list);
    }
    wrap.innerHTML = '<span class="accent">组织树</span> <span class="line"></span><span class="cnt">' + total + ' 人</span>';
  }
  function updateC3OrgLabel(total) {
    var label = document.querySelector('.screen[data-screen="C3"] .section-label');
    if (!label) return;
    label.innerHTML = '<span class="accent">组织树</span> <span class="line"></span><span class="cnt">' + total + ' 人</span>';
  }
  function apiFetch(path, opts) {
    opts = opts || {};
    var base = localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var headers = Object.assign({}, opts.headers || {});
    if (token) headers.Authorization = 'Bearer ' + token;
    if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    return fetch(base + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body || undefined
    }).then(function (r) {
      if (r.status === 401 && typeof window.__dunesHandleSessionRevoked === 'function') {
        window.__dunesHandleSessionRevoked();
        return { success: false, message: '账号已在其他设备登录，请重新登录' };
      }
      return r.json();
    });
  }
  async function startPrivateChat(peerUserId) {
    if (!peerUserId) return;
    if (peerUserId === devUserId()) {
      alert('不能与自己发起私聊');
      return;
    }
    try {
      var j = await apiFetch('/conversations', {
        method: 'POST',
        body: JSON.stringify({
          kind: 'PRIVATE',
          title: '私聊',
          memberUserIds: [peerUserId]
        })
      });
      if (!j.success || !j.data || !j.data.conversationId) {
        alert(j.message || '创建私聊失败');
        return;
      }
      window.pendingContactUserId = peerUserId;
      window.pendingConvId = Number(j.data.conversationId);
      try { pendingConvId = Number(j.data.conversationId); } catch (e) {}
      if (typeof window.__dunesSelectConversation === 'function') {
        window.__dunesSelectConversation(Number(j.data.conversationId), peerUserId);
      }
      window._imNavExplicitConv = true;
      if (typeof window.__dunesResubscribeIm === 'function') window.__dunesResubscribeIm();
      if (typeof go === 'function') go('C5');
      else if (typeof setScreen === 'function') setScreen('C5', false);
    } catch (e) {
      alert('创建私聊失败：' + (e.message || e));
      console.warn('DunesContacts.startPrivateChat', e);
    }
  }
  function personCls(uid) {
    var n = Math.abs(Number(uid) || 0) % 6;
    return 'person-' + ['a', 'b', 'c', 'd', 'e', 'f'][n];
  }
  function renderContactRow(c) {
    var uid = Number(c.userId);
    var me = uid === devUserId() ? '<span class="me-tag">我</span>' : '';
    var nm = contactDisplayName(c);
    var disabledCls = isContactDisabled(c) ? ' contact-disabled' : '';
    return ''
      + '<div class="contact-row tappable' + disabledCls + '" data-go="C9" data-contact-user-id="' + uid + '">'
      + '<div class="cr-av ' + personCls(uid) + '" data-avatar-user-id="' + uid + '">' + esc((c.displayName || '?').slice(0, 1)) + '<div class="av-dot"></div></div>'
      + '<div class="ct-bd"><div class="ct-nm">' + esc(nm) + me + '</div>'
      + '<div class="ct-meta">' + contactMetaHtml(c) + '</div></div>'
      + '<div class="ct-actions">'
      + '<div class="ic-btn primary tappable" data-msg-user-id="' + uid + '" title="发消息"><i class="ti ti-message"></i></div>'
      + '</div></div>';
  }
  function wireDeptToggle(root) {
    root.querySelectorAll('.dept-head').forEach(function (h) {
      if (h.dataset.wiredDept) return;
      h.dataset.wiredDept = '1';
      h.classList.add('tappable');
      h.addEventListener('click', function (e) {
        if (e.target.closest('[data-go],[data-msg-user-id],[data-pick-user-id]')) return;
        h.classList.toggle('expanded');
        var block = h.closest('.dept-block');
        if (!block) return;
        var people = block.querySelector(':scope > .dept-people');
        var kids = block.querySelector(':scope > .dept-children');
        var show = h.classList.contains('expanded');
        if (people) people.style.display = show ? '' : 'none';
        if (kids) kids.style.display = show ? '' : 'none';
      });
    });
  }
  function renderDeptBlock(dep, pickMode, allowDeptSelect) {
    var exp = !!dep.expanded;
    var showDeptSelect = pickMode && allowDeptSelect !== false;
    var selectAll = showDeptSelect
      ? '<button type="button" class="dh-select-all" data-dept-select-all="1">全选</button>'
      : '';
    var head = ''
      + '<div class="dept-head' + (exp ? ' expanded' : '') + '">'
      + '<i class="ti ti-chevron-right dh-chev"></i>'
      + '<div class="dh-ic"><i class="ti ti-building"></i></div>'
      + '<div class="dh-bd"><div class="dh-nm">' + esc(dep.name || '部门') + '</div></div>'
      + selectAll
      + '<div class="dh-cnt">' + (dep.userCount || (dep.users && dep.users.length) || 0) + '</div></div>';
    var peopleHtml = '';
    (dep.users || []).forEach(function (c) {
      peopleHtml += pickMode ? renderPickRow(c) : renderContactRow(c);
    });
    var people = '<div class="dept-people"' + (exp ? '' : ' style="display:none"') + '>' + peopleHtml + '</div>';
    var childHtml = '';
    (dep.children || []).forEach(function (ch) {
      childHtml += renderDeptBlock(ch, pickMode, allowDeptSelect);
    });
    var children = childHtml
      ? '<div class="dept-children"' + (exp ? '' : ' style="display:none"') + '>' + childHtml + '</div>'
      : '';
    return '<div class="dept-block" data-api-dept="1" data-dept-id="' + (dep.id || 0) + '">' + head + people + children + '</div>';
  }
  function memberPickState() {
    return window.__dunesMemberPickState || null;
  }
  function isUserPicked(uid) {
    var ps = memberPickState();
    if (ps && ps.selected && ps.selected.has(uid)) return true;
    return !!(window.c7SelectedIds && window.c7SelectedIds.has(uid));
  }
  function renderPickRow(c) {
    var uid = Number(c.userId);
    if (!uid || uid === devUserId() || isContactDisabled(c)) return '';
    var on = isUserPicked(uid) ? ' on' : '';
    return '<div class="contact-pick-row tappable' + on + '" data-pick-user-id="' + uid + '">'
      + '<div class="cp-check"><i class="ti ti-check"></i></div>'
      + '<div class="cp-av no-initial ' + personCls(uid) + '" data-avatar-user-id="' + uid + '"> </div>'
      + '<div class="cp-bd"><div class="cp-nm">' + esc(contactDisplayName(c)) + '</div>'
      + '<div class="cp-m"><span>' + esc(c.title || '') + '</span>'
      + (c.department ? '<span>' + esc(c.department || '') + '</span>' : '') + '</div></div></div>';
  }
  function pickSelectionSet() {
    var ps = memberPickState();
    if (ps && ps.selected) return ps.selected;
    if (!window.c7SelectedIds) window.c7SelectedIds = new Set();
    return window.c7SelectedIds;
  }
  function afterPickSelectionChange(fromPicker) {
    if (fromPicker) return;
    updateC7SelectedStack();
  }
  function wireDeptSelectAll(root, fromPicker) {
    if (!root) return;
    root.querySelectorAll('[data-dept-select-all]').forEach(function (btn) {
      if (btn.dataset.wiredSelAll) return;
      btn.dataset.wiredSelAll = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        if (!fromPicker && window.c7Mode === 'private') return;
        var block = btn.closest('.dept-block');
        if (!block) return;
        var sel = pickSelectionSet();
        block.querySelectorAll('[data-pick-user-id]').forEach(function (row) {
          var uid = Number(row.getAttribute('data-pick-user-id'));
          if (!uid) return;
          sel.add(uid);
          row.classList.add('on');
        });
        afterPickSelectionChange(fromPicker);
      });
    });
  }
  function ensureC7BulkBar() {
    var stack = document.querySelector('.screen[data-screen="C7"] .selected-stack');
    if (!stack || document.getElementById('c7-bulk-bar')) return;
    var bar = document.createElement('div');
    bar.id = 'c7-bulk-bar';
    bar.className = 'c7-bulk-bar';
    bar.innerHTML = '<button type="button" id="c7-select-all-btn">全选可见成员</button>'
      + '<button type="button" id="c7-clear-all-btn">清空已选</button>';
    stack.parentNode.insertBefore(bar, stack.nextSibling);
    document.getElementById('c7-select-all-btn').addEventListener('click', function () {
      if (window.c7Mode === 'private') return;
      if (!window.c7SelectedIds) window.c7SelectedIds = new Set();
      document.querySelectorAll('#c7-contact-list [data-pick-user-id]').forEach(function (row) {
        var uid = Number(row.getAttribute('data-pick-user-id'));
        if (!uid) return;
        window.c7SelectedIds.add(uid);
        row.classList.add('on');
      });
      updateC7SelectedStack();
    });
    document.getElementById('c7-clear-all-btn').addEventListener('click', function () {
      if (!window.c7SelectedIds) window.c7SelectedIds = new Set();
      window.c7SelectedIds.clear();
      document.querySelectorAll('#c7-contact-list .contact-pick-row.on').forEach(function (row) {
        row.classList.remove('on');
      });
      updateC7SelectedStack();
    });
  }
  function updateC7SelectedStack() {
    var stack = document.querySelector('.screen[data-screen="C7"] .selected-stack');
    if (!stack) return;
    var ids = window.c7SelectedIds ? [...window.c7SelectedIds] : [];
    var label = '<span style="font-family:var(--mono);font-size:9px;color:var(--text-3);letter-spacing:.04em;font-weight:700;text-transform:uppercase;margin-right:2px">已选 '
      + ids.length + '：</span>';
    if (!ids.length) {
      stack.innerHTML = label + '<span style="font-size:11px;color:var(--text-3)">请从组织树选择成员</span>';
      return;
    }
    stack.innerHTML = label + ids.map(function (id) {
      var row = document.querySelector('#c7-contact-list [data-pick-user-id="' + id + '"] .cp-nm');
      var nm = row && row.textContent ? row.textContent.trim() : ('用户' + id);
      return '<span class="ss-tag" data-rm-user-id="' + id + '">' + esc(nm) + '<i class="ti ti-x"></i></span>';
    }).join('');
    stack.querySelectorAll('[data-rm-user-id]').forEach(function (tag) {
      tag.addEventListener('click', function (e) {
        e.stopPropagation();
        var uid = Number(tag.getAttribute('data-rm-user-id'));
        if (window.c7SelectedIds) window.c7SelectedIds.delete(uid);
        document.querySelectorAll('#c7-contact-list [data-pick-user-id="' + uid + '"]').forEach(function (row) {
          row.classList.remove('on');
        });
        updateC7SelectedStack();
      });
    });
  }
  function wirePickRows(root, fromPicker) {
    if (!root) return;
    root.querySelectorAll('[data-pick-user-id]').forEach(function (row) {
      if (row.dataset.wiredPick) return;
      row.dataset.wiredPick = '1';
      row.addEventListener('click', function () {
        var uid = Number(row.getAttribute('data-pick-user-id'));
        if (!uid) return;
        var sel = pickSelectionSet();
        var ps = memberPickState();
        var single = fromPicker ? (ps && ps.single) : (window.c7Mode === 'private');
        if (single) {
          sel.clear();
          root.querySelectorAll('.contact-pick-row.on').forEach(function (r) { r.classList.remove('on'); });
        }
        if (sel.has(uid)) {
          sel.delete(uid);
          row.classList.remove('on');
        } else {
          sel.add(uid);
          row.classList.add('on');
        }
        afterPickSelectionChange(fromPicker);
      });
    });
  }
  function wireC7PickRows(root) { wirePickRows(root, false); }
  async function createC7Conversation() {
    var ids = window.c7SelectedIds ? [...window.c7SelectedIds].filter(function (id) { return id !== devUserId(); }) : [];
    if (!ids.length) {
      alert('请至少选择一位同事');
      return;
    }
    var kind = (window.c7Mode === 'group' || ids.length >= 2) ? 'WORKGROUP' : 'PRIVATE';
    var title = '私聊';
    if (kind === 'WORKGROUP') {
      var dlgTitle = '请输入群名称';
      if (window.DunesDialog && window.DunesDialog.prompt) {
        var picked = await window.DunesDialog.prompt(dlgTitle, '新群聊');
        if (picked == null) return;
        title = picked.trim() || '新群聊';
      } else {
        title = window.prompt(dlgTitle, '新群聊') || '新群聊';
        if (!title.trim()) title = '新群聊';
      }
    }
    try {
      var j = await apiFetch('/conversations', {
        method: 'POST',
        body: JSON.stringify({ kind: kind, title: title, memberUserIds: ids })
      });
      if (!j.success || !j.data || !j.data.conversationId) {
        alert(j.message || '创建失败');
        return;
      }
      window.pendingConvId = Number(j.data.conversationId);
      try { pendingConvId = Number(j.data.conversationId); } catch (e) {}
      if (typeof window.__dunesSelectConversation === 'function') {
        window.__dunesSelectConversation(Number(j.data.conversationId), kind === 'PRIVATE' ? ids[0] : 0);
      } else if (kind === 'PRIVATE') {
        window.pendingContactUserId = ids[0];
        window.__dunesPendingPeerUserId = ids[0];
      } else {
        window.__dunesPendingPeerUserId = null;
      }
      window._imNavExplicitConv = true;
      if (typeof window.__dunesResubscribeIm === 'function') window.__dunesResubscribeIm();
      if (typeof go === 'function') go(kind === 'PRIVATE' ? 'C5' : 'C2');
      else if (typeof setScreen === 'function') setScreen(kind === 'PRIVATE' ? 'C5' : 'C2', false);
    } catch (e) {
      alert('创建失败：' + (e.message || e));
    }
  }
  function wireC7Create() {
    var btn = document.getElementById('c7-create-btn');
    if (!btn || btn.dataset.wiredC7) return;
    btn.dataset.wiredC7 = '1';
    window.c7SelectedIds = window.c7SelectedIds || new Set();
    window.c7Mode = window.c7Mode || 'group';
    document.querySelectorAll('.screen[data-screen="C7"] .new-conv-kinds .nck').forEach(function (nck) {
      if (nck.dataset.wiredNck) return;
      if (nck.classList.contains('nck-disabled')) return;
      nck.dataset.wiredNck = '1';
      nck.classList.add('tappable');
      nck.addEventListener('click', function () {
        document.querySelectorAll('.screen[data-screen="C7"] .new-conv-kinds .nck').forEach(function (x) {
          x.classList.remove('featured');
        });
        nck.classList.add('featured');
        var mode = nck.getAttribute('data-c7-mode') || 'group';
        window.c7Mode = mode === 'private' ? 'private' : 'group';
        if (window.c7Mode === 'private' && window.c7SelectedIds && window.c7SelectedIds.size > 1) {
          var first = window.c7SelectedIds.values().next().value;
          window.c7SelectedIds = new Set(first ? [first] : []);
          document.querySelectorAll('#c7-contact-list .contact-pick-row.on').forEach(function (row) {
            var uid = Number(row.getAttribute('data-pick-user-id'));
            if (!window.c7SelectedIds.has(uid)) row.classList.remove('on');
          });
        }
        updateC7SelectedStack();
      });
    });
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      createC7Conversation();
    });
    updateC7SelectedStack();
  }
  function wireMsgButtons(root) {
    root.querySelectorAll('[data-msg-user-id]').forEach(function (btn) {
      if (btn.dataset.wiredMsg) return;
      btn.dataset.wiredMsg = '1';
      btn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        if (btn.dataset.busy === '1') return;
        var uid = Number(btn.getAttribute('data-msg-user-id'));
        if (!uid) return;
        btn.dataset.busy = '1';
        startPrivateChat(uid).finally(function () { btn.dataset.busy = '0'; });
      });
    });
  }
  function ensureC3SearchBar() {
    var screen = document.querySelector('.screen[data-screen="C3"]');
    if (!screen || document.getElementById('c3-search-wrap')) return;
    var tree = screen.querySelector('.dept-tree');
    var content = screen.querySelector('.content');
    if (!content || !tree) return;
    if (!content.dataset.dunesC3ScrollWired) {
      content.dataset.dunesC3ScrollWired = '1';
      content.addEventListener('scroll', rememberC3Scroll, { passive: true });
    }
    var wrap = document.createElement('div');
    wrap.id = 'c3-search-wrap';
    wrap.className = 'chat-search-wrap';
    wrap.style.display = 'none';
    wrap.style.marginBottom = '8px';
    wrap.innerHTML = '<div class="chat-search"><i class="ti ti-search"></i>'
      + '<input id="c3-search-input" type="search" placeholder="搜索同事 · 姓名 / 部门" autocomplete="off"></div>';
    content.insertBefore(wrap, tree);
    var inp = document.getElementById('c3-search-input');
    inp.addEventListener('input', function () {
      clearTimeout(debounceTimer);
      var q = inp.value.trim();
      debounceTimer = setTimeout(function () { loadC3(q); }, 300);
    });
  }
  function wireC3SearchBtn() {
    var btn = document.querySelector('.screen[data-screen="C3"] .ch-act .ic-btn[title="搜索人"]');
    if (!btn || btn.dataset.wiredC3Search) return;
    btn.dataset.wiredC3Search = '1';
    btn.classList.add('tappable');
    btn.style.cursor = 'pointer';
    btn.setAttribute('role', 'button');
    btn.addEventListener('click', function (e) {
      e.preventDefault();
      e.stopPropagation();
      ensureC3SearchBar();
      var wrap = document.getElementById('c3-search-wrap');
      if (!wrap) return;
      var open = wrap.style.display === 'none';
      wrap.style.display = open ? '' : 'none';
      if (open) {
        var inp = document.getElementById('c3-search-input');
        if (inp) inp.focus();
      }
    });
  }
  async function loadC3(q) {
    var tree = document.querySelector('.screen[data-screen="C3"] .dept-tree');
    var sub = document.querySelector('.screen[data-screen="C3"] .ch-t .sub');
    if (!tree) return;
    tree.innerHTML = '<div class="api-strip"><i class="ti ti-loader"></i><span>加载通讯录…</span></div>';
    try {
      var qs = q ? '&q=' + encodeURIComponent(q) : '';
      var j = await apiFetch('/contacts?view=org' + qs);
      if (!j.success) throw new Error(j.message || 'contacts failed');
      var d = j.data || {};
      var total = d.total || 0;
      var depts = d.departments || [];
      var items = d.items || [];
      if (sub) sub.textContent = 'CONTACTS · ' + total;
      updateC3OrgLabel(total);
      tree.innerHTML = '';
      if (q) {
        if (!items.length) {
          tree.innerHTML = '<div class="api-strip"><span>无匹配联系人</span></div>';
          return;
        }
        items.forEach(function (c) {
          rememberUserProfile(c);
          tree.insertAdjacentHTML('beforeend', renderContactRow(c));
        });
        wireMsgButtons(tree);
        c3Loaded = true;
        c3LastQuery = q;
        restoreC3Scroll();
        hydrateAvatarsIn(tree);
        refreshOnlineDots();
        return;
      }
      if (!depts.length) {
        tree.innerHTML = '<div class="api-strip"><span>暂无组织数据 · 请确认 im-go / flow-go 已启动</span></div>';
        return;
      }
      depts.forEach(function (dep) {
        rememberDeptProfiles(dep);
        tree.insertAdjacentHTML('beforeend', renderDeptBlock(dep, false));
      });
      wireDeptToggle(tree);
      wireDeptSelectAll(tree);
      wireMsgButtons(tree);
      c3Loaded = true;
      c3LastQuery = q || '';
      restoreC3Scroll();
      hydrateAvatarsIn(tree);
      refreshOnlineDots();
    } catch (e) {
      tree.innerHTML = '<div class="api-strip"><span>通讯录加载失败：' + esc(e.message || e) + '</span></div>';
      console.warn('DunesContacts.loadC3', e);
    }
  }
  async function loadC7(q) {
    var box = document.getElementById('c7-contact-list');
    if (!box) return;
    if (!window.c7SelectedIds) window.c7SelectedIds = new Set();
    box.classList.add('dept-tree');
    box.innerHTML = '<div class="api-strip"><i class="ti ti-loader"></i><span>加载组织…</span></div>';
    try {
      var qs = q ? '&q=' + encodeURIComponent(q) : '';
      var j = await apiFetch('/contacts?view=org' + qs);
      if (!j.success) throw new Error(j.message || 'contacts failed');
      var d = j.data || {};
      var depts = d.departments || [];
      var items = d.items || [];
      var total = d.total || 0;
      updateC7OrgLabel(total);
      box.innerHTML = '';
      if (q) {
        items = items.filter(function (c) { return !isContactDisabled(c); });
        if (!items.length) {
          box.innerHTML = '<div class="api-strip"><span>无匹配联系人</span></div>';
          return;
        }
        items.forEach(function (c) {
          rememberUserProfile(c);
          box.insertAdjacentHTML('beforeend', renderPickRow(c));
        });
      } else if (!depts.length) {
        box.innerHTML = '<div class="api-strip"><span>暂无组织数据</span></div>';
        return;
      } else {
        depts.forEach(function (dep) {
          rememberDeptProfiles(dep);
          box.insertAdjacentHTML('beforeend', renderDeptBlock(dep, true));
        });
      }
      var mock = document.getElementById('c7-mock-contacts');
      if (mock) mock.style.display = 'none';
      wireDeptToggle(box);
      wireDeptSelectAll(box);
      wireC7PickRows(box);
      updateC7SelectedStack();
      hydrateAvatarsIn(box);
    } catch (e) {
      box.innerHTML = '<div class="api-strip"><span>加载失败：' + esc(e.message || e) + '</span></div>';
      console.warn('DunesContacts.loadC7', e);
    }
  }
  function refreshOnlineDots() {
    var online = window.__dunesOnlineUserIds || {};
    document.querySelectorAll('.contact-row[data-contact-user-id]').forEach(function (row) {
      var dot = row.querySelector('.av-dot');
      if (!dot) return;
      var uid = Number(row.getAttribute('data-contact-user-id'));
      var on = false;
      if (window.DunesPresence && typeof window.DunesPresence.isUserOnline === 'function') {
        on = window.DunesPresence.isUserOnline(uid);
      } else if (uid) {
        on = !!online[String(uid)];
      }
      dot.classList.toggle('on', on);
    });
  }
  function wireC7Search() {
    var inp = document.querySelector('.screen[data-screen="C7"] .chat-search input');
    if (!inp || inp.dataset.wiredC7Search) return;
    inp.dataset.wiredC7Search = '1';
    inp.addEventListener('input', function () {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(function () { loadC7(inp.value.trim()); }, 300);
    });
  }
  function onScreen(id) {
    if (id === 'C3') {
      ensureC3SearchBar();
      wireC3SearchBtn();
      var inp = document.getElementById('c3-search-input');
      var q = inp ? inp.value.trim() : '';
      if (c3Loaded && q === c3LastQuery) {
        restoreC3Scroll();
      } else {
        loadC3(q);
      }
    }
    if (id === 'C7') {
      wireC7Search();
      wireC7Create();
      ensureC7BulkBar();
      loadC7('');
    }
    if (id === 'C9') {
      var uid = Number(window.pendingContactUserId || pendingContactUserId || 0);
      if (window.DunesApi && typeof window.DunesApi.loadContactDetail === 'function') {
        window.DunesApi.loadContactDetail(uid);
      }
    }
  }
  function openContact(userId) {
    var uid = Number(userId || 0);
    if (!uid) return;
    window.__dunesC9ReturnScreen = document.querySelector('.screen.active')?.dataset?.screen || 'C1';
    window.pendingContactUserId = uid;
    try { pendingContactUserId = uid; } catch (e) {}
    if (typeof go === 'function') go('C9');
  }
  return {
    onScreen: onScreen,
    openContact: openContact,
    loadC3: loadC3,
    loadC7: loadC7,
    wireC7Create: wireC7Create,
    createC7Conversation: createC7Conversation,
    startPrivateChat: startPrivateChat,
    refreshOnlineDots: refreshOnlineDots,
    renderDeptBlock: renderDeptBlock,
    wireDeptToggle: wireDeptToggle,
    wireDeptSelectAll: wireDeptSelectAll,
    wirePickRows: wirePickRows
  };
})();
window.__dunesContactsPick = window.DunesContacts;
''';

  /// C1 消息首页：用 im-go `/conversations` + `/notifications` 渲染，替换静态 mock 行（不改 UI 样式类名）。
  static const _inboxJs = r'''
window.DunesInbox = (function () {
  var searchWired = false;
  var _c1RefreshTimer = null;
  var _c1Loaded = false;
  var HIDDEN_C1_KEY = 'dunes_c1_hidden_conversations_v1';
  var C1_SWIPE_W = 72;
  var _c1SwipeOpen = null;
  function readHiddenConvMap() {
    try {
      var raw = localStorage.getItem(HIDDEN_C1_KEY);
      if (!raw) return {};
      var j = JSON.parse(raw);
      return j && typeof j === 'object' ? j : {};
    } catch (e) { return {}; }
  }
  function writeHiddenConvMap(map) {
    try { localStorage.setItem(HIDDEN_C1_KEY, JSON.stringify(map || {})); } catch (e) {}
  }
  function normalizeHiddenEntry(v) {
    if (typeof v === 'number') return { at: v, permanent: false };
    return { at: (v && v.at) || Date.now(), permanent: !!(v && v.permanent) };
  }
  function isConvPermanentlyHidden(convId) {
    if (!convId) return false;
    var entry = readHiddenConvMap()[String(convId)];
    if (entry == null) return false;
    return normalizeHiddenEntry(entry).permanent;
  }
  function isSystemMsgKind(kind) {
    kind = String(kind || '').toUpperCase();
    return kind.indexOf('SYSTEM') === 0;
  }
  function isConvHidden(convId) {
    if (!convId) return false;
    return !!readHiddenConvMap()[String(convId)];
  }
  function hideConvLocally(convId, permanent) {
    if (!convId) return;
    var map = readHiddenConvMap();
    map[String(convId)] = { at: Date.now(), permanent: !!permanent };
    writeHiddenConvMap(map);
  }
  function finishExitGroup(convId, msg, permanent) {
    if (convId) hideConvLocally(convId, permanent !== false);
    window.pendingConvId = 0;
    try { pendingConvId = 0; } catch (e) {}
    window.__dunesActiveConvId = null;
    if (msg) toast(msg);
    if (typeof go === 'function') go('C1');
    else if (typeof setScreen === 'function') setScreen('C1', false);
    if (window.DunesInbox && window.DunesInbox.loadC1) window.DunesInbox.loadC1();
    if (window.DunesInbox && typeof window.DunesInbox.refreshNovaInboxPreview === 'function') {
      window.DunesInbox.refreshNovaInboxPreview();
    }
  }
  function unhideConvLocally(convId) {
    if (!convId) return;
    var map = readHiddenConvMap();
    var entry = map[String(convId)];
    if (entry == null) return;
    if (normalizeHiddenEntry(entry).permanent) return;
    delete map[String(convId)];
    writeHiddenConvMap(map);
  }
  function isDissolvedConv(c) {
    return !!(c && (c.dissolved || c.isDissolved || c.status === 'DISSOLVED' || c.frozen));
  }
  function filterVisibleConvs(convs) {
    return (convs || []).filter(function (c) {
      if (!c || !c.id || isConvHidden(c.id)) return false;
      if (isDissolvedConv(c)) return false;
      var st = String(c.membershipStatus || c.memberStatus || '').toUpperCase();
      if (st === 'LEFT' || st === 'REMOVED') return false;
      return true;
    });
  }
  function purgeDissolvedConvsFromServer(convs) {
    (convs || []).forEach(function (c) {
      if (!c || !c.id || !isDissolvedConv(c)) return;
      hideConvLocally(c.id, true);
      exitGroupMembership(c.id, true).catch(function () {});
    });
  }
  function upgradeDissolvedHiddenConvs(convs) {
    var map = readHiddenConvMap();
    var changed = false;
    (convs || []).forEach(function (c) {
      if (!c || !c.id) return;
      var dissolved = !!(c.dissolved || c.isDissolved || c.status === 'DISSOLVED' || c.frozen);
      if (!dissolved || !map[String(c.id)]) return;
      if (!normalizeHiddenEntry(map[String(c.id)]).permanent) {
        map[String(c.id)] = { at: Date.now(), permanent: true };
        changed = true;
      }
    });
    if (changed) writeHiddenConvMap(map);
  }
  function isSwipeableConvKind(kind) {
    kind = String(kind || '').toUpperCase();
    return kind === 'PRIVATE' || kind === 'WORKGROUP' || kind === 'GROUP' || kind === 'WORKGROUP_APPROVAL';
  }
  function wrapSwipeRow(convId, rowHtml) {
    return '<div class="c1-swipe-item" data-conv-id="' + convId + '">'
      + '<div class="c1-swipe-actions"><button type="button" class="c1-swipe-delete">删除</button></div>'
      + '<div class="c1-swipe-content">' + rowHtml + '</div></div>';
  }
  function findC1ConvRow(list, convId) {
    if (!list || !convId) return null;
    var wrap = list.querySelector('.c1-swipe-item[data-conv-id="' + convId + '"]');
    if (wrap) return wrap.querySelector('.chat-row');
    return list.querySelector('.chat-row[data-conv-id="' + convId + '"]');
  }
  function shouldUnhideFromEvent(data) {
    if (!data) return false;
    if (data.type === 'message' || data.type === 'system_flow') {
      var convId = Number(data.conversationId || (data.message && data.message.conversationId) || 0);
      if (convId && isConvPermanentlyHidden(convId)) return false;
      var me = Number(localStorage.getItem('dunes_user_id') || '0');
      if (data.message && data.message.sender && Number(data.message.sender.userId) !== me) {
        if (isSystemMsgKind(data.message.kind)) return false;
        return true;
      }
    }
    return false;
  }
  async function exitGroupMembership(convId, dissolved) {
    var me = Number(localStorage.getItem('dunes_user_id') || '0');
    try {
      var j = await apiFetch('/conversations/' + convId + '/leave', { method: 'POST' });
      if (j && j.success) return true;
      var apiMsg = String((j && j.message) || '退出失败');
      if (!dissolved && !/dissolved|解散|group dissolved/i.test(apiMsg)) throw new Error(apiMsg);
    } catch (err) {
      var errMsg = String((err && err.message) || '退出失败');
      if (!dissolved && !/dissolved|解散|group dissolved/i.test(errMsg)) throw err;
    }
    if (me > 0) {
      try {
        var dj = await apiFetch('/conversations/' + convId + '/members/' + me, { method: 'DELETE' });
        if (dj && dj.success) return true;
      } catch (e) {}
    }
    return false;
  }
  function closeC1SwipeOpen() {
    if (_c1SwipeOpen) {
      _c1SwipeOpen.classList.remove('open');
      var content = _c1SwipeOpen.querySelector('.c1-swipe-content');
      if (content) content.style.transform = '';
      _c1SwipeOpen = null;
    }
  }
  function refreshC1SectionCounts(list) {
    if (!list) return;
    list.querySelectorAll('.chat-section[data-section-key]').forEach(function (header) {
      var key = header.getAttribute('data-section-key');
      if (key === 'ai') return;
      var cnt = 0;
      var n = header.nextElementSibling;
      while (n && !(n.classList && n.classList.contains('chat-section'))) {
        if (n.classList.contains('c1-swipe-item')) cnt++;
        else if (n.classList.contains('chat-row') && !n.closest('.c1-swipe-item')) cnt++;
        n = n.nextElementSibling;
      }
      var badge = header.querySelector('.cnt');
      if (badge) badge.textContent = String(cnt);
      header.style.display = cnt > 0 ? '' : 'none';
    });
  }
  async function requestDeleteConv(item) {
    if (!item) return;
    var convId = Number(item.getAttribute('data-conv-id'));
    if (!convId) return;
    closeC1SwipeOpen();
    var titleEl = item.querySelector('.cr-nm');
    var title = titleEl ? String(titleEl.textContent || '').trim().slice(0, 24) : '该会话';
    var msg = '删除「' + title + '」后将不再显示在列表中，有新消息时会重新出现。确定删除吗？';
    var ok = false;
    if (window.DunesDialog && typeof window.DunesDialog.confirm === 'function') {
      ok = await window.DunesDialog.confirm(msg);
    } else {
      ok = confirm(msg);
    }
    if (!ok) return;
    hideConvLocally(convId);
    item.remove();
    var list = document.getElementById('c1-conv-list');
    refreshC1SectionCounts(list);
    if (typeof recalcCommBadgeFromDom === 'function') recalcCommBadgeFromDom();
  }
  function wireC1SwipeDelete(root) {
    if (!root) return;
    root.querySelectorAll('.c1-swipe-item:not([data-swipe-wired])').forEach(function (item) {
      item.dataset.swipeWired = '1';
      var content = item.querySelector('.c1-swipe-content');
      var deleteBtn = item.querySelector('.c1-swipe-delete');
      if (!content) return;
      if (deleteBtn) {
        deleteBtn.addEventListener('click', function (e) {
          e.preventDefault();
          e.stopPropagation();
          requestDeleteConv(item);
        });
      }
      var startX = 0;
      var startY = 0;
      var baseX = 0;
      var dragging = false;
      var locked = false;
      function onStart(clientX, clientY) {
        closeC1SwipeOpen();
        startX = clientX;
        startY = clientY;
        baseX = item.classList.contains('open') ? -C1_SWIPE_W : 0;
        dragging = false;
        locked = false;
        content.style.transition = 'none';
      }
      function onMove(clientX, clientY, prevent) {
        var dx = clientX - startX;
        var dy = clientY - startY;
        if (!dragging && !locked) {
          if (Math.abs(dy) > Math.abs(dx) && Math.abs(dy) > 8) { locked = true; return; }
          if (Math.abs(dx) > 8) dragging = true;
        }
        if (!dragging || locked) return;
        var x = Math.min(0, Math.max(-C1_SWIPE_W, baseX + dx));
        content.style.transform = 'translateX(' + x + 'px)';
        if (prevent && Math.abs(dx) > 4) prevent();
      }
      function onEnd() {
        content.style.transition = '';
        if (!dragging || locked) return;
        var tx = content.style.transform || '';
        var x = 0;
        var m = tx.match(/-?\d+(\.\d+)?/);
        if (m) x = parseFloat(m[0]) || 0;
        if (x <= -C1_SWIPE_W * 0.45) {
          item.classList.add('open');
          content.style.transform = '';
          _c1SwipeOpen = item;
        } else {
          item.classList.remove('open');
          content.style.transform = '';
        }
      }
      content.addEventListener('touchstart', function (e) {
        if (e.touches.length !== 1) return;
        onStart(e.touches[0].clientX, e.touches[0].clientY);
      }, { passive: true });
      content.addEventListener('touchmove', function (e) {
        if (e.touches.length !== 1) return;
        onMove(e.touches[0].clientX, e.touches[0].clientY, function () { e.preventDefault(); });
      }, { passive: false });
      content.addEventListener('touchend', onEnd);
      content.addEventListener('touchcancel', onEnd);
      content.addEventListener('mousedown', function (e) {
        if (e.button !== 0) return;
        onStart(e.clientX, e.clientY);
        function mm(ev) { onMove(ev.clientX, ev.clientY, null); }
        function mu() {
          document.removeEventListener('mousemove', mm);
          document.removeEventListener('mouseup', mu);
          onEnd();
        }
        document.addEventListener('mousemove', mm);
        document.addEventListener('mouseup', mu);
      });
    });
    if (root.dataset.c1SwipeCloseWired) return;
    root.dataset.c1SwipeCloseWired = '1';
    root.addEventListener('click', function (e) {
      if (e.target.closest('.c1-swipe-delete')) return;
      if (e.target.closest('.c1-swipe-item.open')) return;
      closeC1SwipeOpen();
    }, true);
  }
  function c1ContentEl() {
    return document.querySelector('.screen[data-screen="C1"] .content');
  }
  function rememberC1Scroll() {
    var c = c1ContentEl();
    if (!c) return;
    window.__dunesC1ScrollTop = c.scrollTop;
  }
  function restoreC1Scroll() {
    var c = c1ContentEl();
    if (!c) return;
    var top = Number(window.__dunesC1ScrollTop || 0);
    setTimeout(function () { c.scrollTop = top; }, 0);
  }
  function esc(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/"/g, '&quot;');
  }
  function formatBodyHtml(s) {
    return esc(s).replace(/\r\n/g, '\n').replace(/\n/g, '<br>');
  }
  function compactMessagePreview(kind, text) {
    var k = String(kind || '').toUpperCase();
    var s = String(text || '').trim();
    if (k === 'IMAGE' || /^\[(相册|拍照|图片)\]/.test(s)) return '发送了一张图片';
    if (k === 'AUDIO' || /^\[语音\]/.test(s)) return '发送了一条语音';
    if (k === 'FILE' || /^\[文件\]/.test(s)) return '发送了一个文件';
    if (/\.(png|jpe?g|gif|webp|bmp|heic|heif)$/i.test(s)) return '发送了一张图片';
    if (/\.(pdf|docx?|xlsx?|pptx?|zip|rar|7z|txt|csv|md|pages|numbers|key)$/i.test(s)) return '发送了一个文件';
    return s;
  }
  function isSystemMsgKind(kind) {
    var k = String(kind || '').toUpperCase();
    return k === 'SYSTEM' || k === 'SYSTEM_JOIN' || k === 'SYSTEM_LEAVE' || k === 'SYSTEM_REMOVE' || k === 'SYSTEM_FLOW';
  }
  function isGroupConvKind(kind) {
    var k = String(kind || '').toUpperCase();
    return k === 'WORKGROUP' || k === 'WORKGROUP_APPROVAL' || k === 'GROUP';
  }
  function splitPreviewSender(text) {
    var s = String(text || '').trim();
    var m = s.match(/^([^:：]{1,24})[:：]\s*(.+)$/);
    if (!m) return { sender: '', body: s };
    return { sender: m[1].trim(), body: m[2].trim() };
  }
  window.__dunesConvPreviewMeta = window.__dunesConvPreviewMeta || {};
  function rememberConvPreviewMeta(convId, preview, kind, at) {
    if (!convId || !preview) return;
    var parsed = splitPreviewSender(preview);
    if (!parsed.sender) return;
    window.__dunesConvPreviewMeta[String(convId)] = {
      senderName: parsed.sender,
      body: parsed.body,
      kind: kind || '',
      at: at || null
    };
  }
  function cacheConvPreviewSender(convId, senderName, kind, text, at) {
    if (!convId || !senderName) return;
    var body = compactMessagePreview(kind, text);
    window.__dunesConvPreviewMeta[String(convId)] = {
      senderName: String(senderName).trim(),
      body: body,
      kind: kind || '',
      at: at || null
    };
  }
  function previewBodyMatches(cachedBody, nextBody, kind) {
    if (!cachedBody || !nextBody) return false;
    if (cachedBody === nextBody) return true;
    return compactMessagePreview(kind, cachedBody) === nextBody;
  }
  function enrichGroupPreview(convId, preview, isGroupRow, row) {
    if (!isGroupRow || !preview) return preview;
    if (preview.indexOf(':') >= 0 || preview.indexOf('：') >= 0) {
      rememberConvPreviewMeta(convId, preview);
      return preview;
    }
    var sender = '';
    if (row) {
      var pv = row.querySelector('.cr-pv');
      var prevParsed = splitPreviewSender(pv ? pv.textContent : '');
      if (prevParsed.sender && previewBodyMatches(prevParsed.body, preview)) sender = prevParsed.sender;
    }
    if (!sender) {
      var cached = window.__dunesConvPreviewMeta[String(convId)];
      if (cached && cached.senderName && previewBodyMatches(cached.body, preview, cached.kind)) {
        sender = cached.senderName;
      }
    }
    if (sender) {
      preview = sender + ': ' + preview;
      rememberConvPreviewMeta(convId, preview);
    }
    return preview;
  }
  function lastSenderNameFromConv(c) {
    if (!c) return '';
    if (c.lastMessageSenderDisplayName) return String(c.lastMessageSenderDisplayName);
    if (c.lastSenderDisplayName) return String(c.lastSenderDisplayName);
    if (c.lastMessageSenderName) return String(c.lastMessageSenderName);
    if (c.lastSenderName) return String(c.lastSenderName);
    if (c.lastMessageSender && c.lastMessageSender.displayName) return String(c.lastMessageSender.displayName);
    if (c.lastSender && c.lastSender.displayName) return String(c.lastSender.displayName);
    var uid = Number(c.lastMessageSenderUserId || c.lastSenderUserId
      || (c.lastMessageSender && c.lastMessageSender.userId) || (c.lastSender && c.lastSender.userId) || 0);
    var me = Number(localStorage.getItem('dunes_user_id') || '0');
    if (uid && uid === me) {
      var mine = localStorage.getItem('dunes_display_name') || '';
      if (mine) return mine;
    }
    if (uid && typeof profileForUserId === 'function') {
      var p = profileForUserId(uid);
      if (p && p.displayName) return p.displayName;
    }
    return splitPreviewSender(c.lastMessagePreview || '').sender;
  }
  function groupPreviewWithSender(kind, text, senderName) {
    if (isSystemMsgKind(kind)) return compactMessagePreview(kind, text);
    var parsed = splitPreviewSender(text);
    var bodyText = parsed.body || text;
    var body = compactMessagePreview(kind, bodyText);
    senderName = String(senderName || parsed.sender || '').trim();
    if (!senderName) return body;
    if (body.indexOf(senderName + ':') === 0) return body;
    return senderName + ': ' + body;
  }
  function convPreviewText(c) {
    if (!c) return '';
    var kind = c.lastMessageKind || c.lastKind || c.messageKind || '';
    var text = c.lastMessagePreview || '';
    if (isGroupConvKind(c.kind)) {
      var preview = groupPreviewWithSender(kind, text, lastSenderNameFromConv(c));
      preview = enrichGroupPreview(c.id, preview, true, null);
      return preview;
    }
    return compactMessagePreview(kind, text);
  }
  function eventPreviewText(data, opts) {
    opts = opts || {};
    if (!data) return '';
    var kind = '';
    var text = '';
    var senderName = '';
    var convId = data.conversationId || data.id || 0;
    if (data.message) {
      kind = data.message.kind;
      text = data.message.bodyText || '';
      senderName = (data.message.sender && data.message.sender.displayName)
        || data.message.senderDisplayName || '';
      if (!senderName) {
        var sid = Number((data.message.sender && data.message.sender.userId) || data.message.senderUserId || 0);
        var me = Number(localStorage.getItem('dunes_user_id') || '0');
        if (sid && sid === me) senderName = localStorage.getItem('dunes_display_name') || '';
      }
    } else {
      kind = data.lastMessageKind || data.lastKind || data.messageKind || '';
      text = data.lastMessagePreview || '';
      senderName = lastSenderNameFromConv(data);
    }
    var preview;
    if (opts.group || isGroupConvKind(data.kind || data.conversationKind)) {
      preview = groupPreviewWithSender(kind, text, senderName);
      if (convId) preview = enrichGroupPreview(convId, preview, true, opts.row || null);
    } else {
      preview = compactMessagePreview(kind, text);
    }
    return preview;
  }
  function apiFetch(path, opts) {
    opts = opts || {};
    var base = localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var headers = Object.assign({}, opts.headers || {});
    if (token) headers.Authorization = 'Bearer ' + token;
    if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    return fetch(base + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body || undefined
    }).then(function (r) {
      if (r.status === 401 && typeof window.__dunesHandleSessionRevoked === 'function') {
        window.__dunesHandleSessionRevoked();
        return { success: false, message: '账号已在其他设备登录，请重新登录' };
      }
      return r.json();
    });
  }
  function personCls(seed) {
    var n = Math.abs(Number(seed) || 0) % 6;
    return 'person-' + ['a', 'b', 'c', 'd', 'e', 'f'][n];
  }
  function formatTime(at) {
    return formatTimeDetailed(at, false);
  }
  function formatTimeDetailed(at, withClock) {
    if (!at) return '';
    var d = new Date(at);
    if (isNaN(d.getTime())) return '';
    var now = new Date();
    var hm = String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
    if (d.toDateString() === now.toDateString()) return withClock ? hm : hm;
    var diff = (now - d) / 86400000;
    if (diff < 1) return withClock ? '昨天 ' + hm : '昨天';
    if (diff < 2) return withClock ? '前天 ' + hm : '前天';
    return (d.getMonth() + 1) + '-' + d.getDate();
  }
  function deptTitleHtml(dept, title) {
    var parts = [];
    if (dept) parts.push(dept);
    if (title) parts.push(title);
    if (!parts.length) return '';
    return ' <span class="role">' + esc(parts.join(' · ')) + '</span>';
  }
  function privateConvRow(c) {
    var peerName = c.peerDisplayName || c.title || '私聊';
    var peerId = Number(c.peerUserId || 0);
    rememberUserProfile({
      userId: peerId,
      displayName: peerName,
      avatarPreset: c.peerAvatarPreset,
      avatarObjectKey: c.peerAvatarObjectKey
    });
    var seed = peerId || Number(c.id);
    var initial = (peerName || '?').slice(0, 1);
    var tm = formatTimeDetailed(c.lastMessageAt, true);
    var preview = formatBodyHtml(convPreviewText(c));
    var meta = c.unreadCount
      ? '<div class="cr-meta"><span class="badge-num accent">' + c.unreadCount + '</span></div>'
      : '';
    var sub = c.peerTitle || c.peerRoleLabel || '';
    return wrapSwipeRow(c.id, '<div class="chat-row tappable" data-go="C5" data-conv-id="' + c.id + '" data-peer-user-id="' + peerId + '" data-contact-user-id="' + peerId + '" data-last-at="' + esc(c.lastMessageAt || '') + '">'
      + '<div class="cr-av ' + personCls(seed) + '" data-open-contact="1" data-avatar-user-id="' + peerId + '">' + esc(initial) + '<div class="av-dot"></div></div>'
      + '<div class="cr-bd"><div class="cr-top"><div class="cr-nm">' + esc(peerName)
      + deptTitleHtml(c.peerDepartment, sub) + '</div><div class="cr-tm">' + esc(tm) + '</div></div>'
      + '<div class="cr-pv">' + preview + '</div></div>' + meta + '</div>');
  }
  function section(icon, label, cnt, rows, pin, key, ts) {
    var iconHtml = key === 'ai' && window.dunesNovaIconHtml
      ? '<span class="chat-section-nova-ic">' + window.dunesNovaIconHtml('nova-ic-sm') + '</span>'
      : '<i class="ti ' + icon + '"></i>';
    return '<div class="chat-section' + (pin ? ' pin' : '') + '" data-section-key="' + esc(key || '') + '" data-section-ts="' + (ts || 0) + '">' + iconHtml
      + esc(label) + '<span class="cnt">' + cnt + '</span></div>' + rows;
  }
  function rowTs(c) {
    if (!c || !c.lastMessageAt) return 0;
    var t = new Date(c.lastMessageAt).getTime();
    return isNaN(t) ? 0 : t;
  }
  function pinTs(c) {
    if (!c || !c.pinnedAt) return 0;
    var t = new Date(c.pinnedAt).getTime();
    return isNaN(t) ? 0 : t;
  }
  function sortConvList(rows) {
    return (rows || []).slice().sort(function (a, b) {
      var ap = a.pinned ? 1 : 0;
      var bp = b.pinned ? 1 : 0;
      if (ap !== bp) return bp - ap;
      if (ap && bp) {
        var pt = pinTs(b) - pinTs(a);
        if (pt !== 0) return pt;
      }
      return rowTs(b) - rowTs(a);
    });
  }
  function maxConvTs(rows) {
    var max = 0;
    (rows || []).forEach(function (c) {
      var t = rowTs(c);
      if (t > max) max = t;
    });
    return max;
  }
  var YUNSHU_NAME = '云枢';
  var YUNSHU_INTRO = '你好，我是你的云枢助手';
  function assistantDisplayTitle(c) {
    // 通讯列表固定展示云枢；会话 title 仅用于 C11 历史列表区分多轮对话
    return YUNSHU_NAME;
  }
  function stripMarkdownPreview(text) {
    return String(text || '')
      .replace(/\*\*([^*]+)\*\*/g, '$1')
      .replace(/\*([^*]+)\*/g, '$1')
      .replace(/^#+\s*/gm, '')
      .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
      .replace(/\s+/g, ' ')
      .trim();
  }
  function assistantPreview(text) {
    var s = stripMarkdownPreview(text);
    if (!s || isNovaWelcomePreview(s)) return YUNSHU_INTRO;
    if (s.length > 48) s = s.slice(0, 48) + '…';
    return s;
  }
  function isNovaWelcomePreview(text) {
    text = String(text || '').trim();
    if (!text) return true;
    if (text.indexOf('你好，我是你的云枢助手') === 0) return true;
    if (text.indexOf('沙丘助手') >= 0) return true;
    return false;
  }
  function novaGeneratingPreviewHtml(status) {
    var s = esc(status || '正在生成…');
    return '<span class="generating"><i class="ti ti-loader ti-spin"></i> ' + s + '</span>';
  }
  function novaLatestConvIdFromHistory() {
    try {
      var local = JSON.parse(localStorage.getItem('dunes_nova_local_history') || '[]');
      var best = 0;
      var bestAt = 0;
      (local || []).forEach(function (t) {
        var id = Number(t.conversationId || t.id || 0);
        var at = new Date(t.lastMessageAt || 0).getTime();
        if (id > 0 && at >= bestAt) { bestAt = at; best = id; }
      });
      return best;
    } catch (e) { return 0; }
  }
  function novaActiveConvId() {
    var saved = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
    if (saved > 0) return saved;
    return novaLatestConvIdFromHistory();
  }
  function findNovaInboxRow(convId) {
    var list = document.getElementById('c1-conv-list');
    if (!list) return null;
    var active = novaActiveConvId();
    var tryId = Number(convId || active || 0);
    var row = null;
    if (tryId > 0) row = list.querySelector('.chat-row[data-conv-id="' + tryId + '"]');
    if (!row) row = list.querySelector('.chat-row[data-go="C4"]');
    if (!row) {
      list.querySelectorAll('.chat-row.pinned').forEach(function (r) {
        if (!row && r.querySelector('.cr-av.ai-bot')) row = r;
      });
    }
    return row;
  }
  function readNovaPersistedGenerating(convId) {
    var ids = [];
    var active = novaActiveConvId();
    if (Number(convId || 0) > 0) ids.push(Number(convId));
    if (active > 0 && ids.indexOf(active) < 0) ids.push(active);
    for (var i = 0; i < ids.length; i++) {
      try {
        var raw = sessionStorage.getItem('dunes_nova_generating_' + String(ids[i]));
        if (!raw) continue;
        var o = JSON.parse(raw);
        if (!o || Date.now() - Number(o.at || 0) > 15 * 60 * 1000) continue;
        return o;
      } catch (e) {}
    }
    return null;
  }
  function novaLocalTurnForConv(convId) {
    try {
      var local = JSON.parse(localStorage.getItem('dunes_nova_local_history') || '[]');
      var cid = Number(convId || 0);
      for (var i = 0; i < local.length; i++) {
        if (Number(local[i].conversationId) === cid) return local[i];
      }
    } catch (e) {}
    return null;
  }
  function novaSessionPreviewForConv(convId) {
    try {
      var raw = localStorage.getItem('dunes_nova_msgs_' + String(convId || 0));
      if (!raw) return { text: '', at: 0 };
      var items = JSON.parse(raw);
      for (var i = items.length - 1; i >= 0; i--) {
        var m = items[i];
        if (!m) continue;
        var role = String(m.role || '').toLowerCase();
        var kind = String(m.kind || '').toUpperCase();
        if (role === 'assistant' || kind.indexOf('AI') >= 0) {
          return {
            text: String(m.bodyText || m.content || '').trim(),
            at: new Date(m.createdAt || 0).getTime()
          };
        }
      }
    } catch (e) {}
    return { text: '', at: 0 };
  }
  function novaConvPreviewText(c) {
    var originalId = Number(c.id || 0);
    var cid = originalId;
    if (String(c.kind || '').toUpperCase() === 'AI_ASSISTANT') {
      var active = novaActiveConvId();
      if (active > 0) cid = active;
    }
    var session = novaSessionPreviewForConv(cid);
    if (session.text && !isNovaWelcomePreview(session.text)) return session.text;
    var localTurn = novaLocalTurnForConv(cid);
    if (localTurn && localTurn.lastMessagePreview && !isNovaWelcomePreview(localTurn.lastMessagePreview)) {
      return localTurn.lastMessagePreview;
    }
    if (cid > 0 && originalId > 0 && cid !== originalId) return '';
    var serverPreview = String(c.lastMessagePreview || '');
    if (serverPreview && !isNovaWelcomePreview(serverPreview)) return serverPreview;
    return '';
  }
  function novaConvPreview(c) {
    var cid = Number(c.id || 0);
    var gen = readNovaPersistedGenerating(cid);
    if (c.assistantGenerating || (gen && gen.status)) {
      return novaGeneratingPreviewHtml(c.assistantGeneratingStatus || (gen && gen.status) || '正在生成…');
    }
    return esc(assistantPreview(novaConvPreviewText(c)));
  }
  function patchNovaGeneratingPreview(convId, generating, status, normalPreview) {
    var list = document.getElementById('c1-conv-list');
    if (!list || !list.classList.contains('dunes-api-ready')) return;
    var active = novaActiveConvId();
    if (active > 0) convId = active;
    var row = findNovaInboxRow(convId);
    if (!row) return;
    if (convId) row.setAttribute('data-conv-id', String(convId));
    var pv = row.querySelector('.cr-pv');
    if (!pv) return;
    if (generating) {
      if (!row.dataset.previewNormal) row.dataset.previewNormal = pv.innerHTML;
      pv.innerHTML = novaGeneratingPreviewHtml(status);
      row.classList.add('nova-generating');
      return;
    }
    row.classList.remove('nova-generating');
    var previewText = normalPreview;
    if (previewText == null || previewText === '') {
      var cid = Number(convId || row.dataset.convId || active || 0);
      if (cid) previewText = novaConvPreviewText({ id: cid, kind: 'AI_ASSISTANT', lastMessagePreview: '' });
    }
    if (previewText !== undefined) {
      pv.innerHTML = esc(assistantPreview(previewText || ''));
      delete row.dataset.previewNormal;
    } else if (row.dataset.previewNormal) {
      pv.innerHTML = row.dataset.previewNormal;
      delete row.dataset.previewNormal;
    }
  }
  function refreshNovaInboxPreview() {
    var list = document.getElementById('c1-conv-list');
    if (!list || !list.classList.contains('dunes-api-ready')) return;
    var active = novaActiveConvId();
    var row = findNovaInboxRow(active);
    if (!row) return;
    if (active > 0) {
      row.setAttribute('data-conv-id', String(active));
    }
    var gen = readNovaPersistedGenerating(active);
    var pv = row.querySelector('.cr-pv');
    if (!pv) return;
    if (gen && gen.status) {
      if (!row.dataset.previewNormal) row.dataset.previewNormal = pv.innerHTML;
      pv.innerHTML = novaGeneratingPreviewHtml(gen.status);
      row.classList.add('nova-generating');
      return;
    }
    row.classList.remove('nova-generating');
    pv.innerHTML = novaConvPreview({
      id: active || Number(row.dataset.convId || 0),
      kind: 'AI_ASSISTANT',
      lastMessagePreview: ''
    });
  }
  function convRow(c) {
    var kind = String(c.kind || '').toUpperCase();
    if (kind === 'AI_ASSISTANT') {
      var activeId = novaActiveConvId();
      if (activeId > 0) {
        c = Object.assign({}, c, {
          id: activeId,
          lastMessagePreview: activeId === Number(c.id || 0) ? c.lastMessagePreview : ''
        });
      }
    }
    var go = kind === 'AI_ASSISTANT' ? 'C4' : kind === 'BROADCAST' ? 'C10' : kind === 'PRIVATE' ? 'C5' : 'C2';
    var rowCls = 'chat-row tappable';
    if (kind === 'AI_ASSISTANT') rowCls = 'chat-row pinned';
    else if (kind === 'BROADCAST') rowCls = 'chat-row broadcast pinned';
    else if (kind === 'WORKGROUP_APPROVAL') rowCls = 'chat-row workgroup-approval' + (c.pinned ? ' pinned' : '') + ' tappable';
    else if (c.pinned) rowCls += ' pinned';
    var avCls = 'cr-av ';
    var avInner = '';
    if (kind === 'AI_ASSISTANT') {
      avCls += 'ai-bot';
      avInner = window.dunesNovaIconHtml ? window.dunesNovaIconHtml() : '<i class="ti ti-sparkles"></i>';
    } else if (kind === 'BROADCAST') {
      avCls += 'broadcast';
      avInner = '<i class="ti ti-broadcast"></i>';
    } else if (kind === 'WORKGROUP_APPROVAL') {
      avCls += 'workgroup-approval';
      avInner = '<i class="ti ti-clipboard-text"></i>';
    } else if (kind === 'PRIVATE') {
      avCls += personCls(c.id);
      avInner = esc((c.title || '?').slice(0, 1)) + '<div class="av-dot"></div>';
    } else {
      avCls += 'group';
      avInner = '<i class="ti ti-users"></i>';
    }
    var mc = '';
    if (kind !== 'BROADCAST' && kind !== 'AI_ASSISTANT' && c.memberCount) {
      mc = ' <span class="cnt">(' + c.memberCount + ')</span>';
    }
    var tm = formatTime(c.lastMessageAt);
    var preview = kind === 'AI_ASSISTANT' ? novaConvPreview(c) : formatBodyHtml(convPreviewText(c));
    if (c.businessType) {
      preview = '<span class="sys-tag">' + esc(String(c.businessType)) + '</span>' + preview;
    }
    var meta = '';
    var mutedMark = '';
    if (c.muted && kind !== 'PRIVATE' && kind !== 'AI_ASSISTANT' && kind !== 'BROADCAST') {
      mutedMark = '<span class="muted"><i class="ti ti-volume-off"></i></span>';
    }
    if (c.unreadCount) {
      meta = '<div class="cr-meta">' + mutedMark + '<span class="badge-num accent">' + c.unreadCount + '</span></div>';
    } else if (mutedMark) {
      meta = '<div class="cr-meta">' + mutedMark + '</div>';
    }
    var aiMark = kind === 'AI_ASSISTANT' ? ' <span class="ai-mark">AI</span>' : '';
    var roleSpan = '';
    var rowHtml = '<div class="' + rowCls + '" data-go="' + go + '" data-conv-id="' + c.id + '" data-last-at="' + esc(c.lastMessageAt || '') + '">'
      + '<div class="' + avCls + '">' + avInner + '</div>'
      + '<div class="cr-bd"><div class="cr-top"><div class="cr-nm">' + esc(kind === 'AI_ASSISTANT' ? assistantDisplayTitle(c) : (c.title || '会话')) + aiMark + roleSpan + mc + '</div>'
      + '<div class="cr-tm">' + esc(tm) + '</div></div><div class="cr-pv">' + preview + '</div></div>'
      + meta + '</div>';
    if (isSwipeableConvKind(kind)) return wrapSwipeRow(c.id, rowHtml);
    return rowHtml;
  }
  function systemRow(n, unread) {
    var pvBody = n && n.body ? formatBodyHtml(n.body) : '';
    var pv = n ? esc(n.title || '') + (pvBody ? '<br>' + pvBody : '') : '暂无新通知';
    var tag = n && n.kind ? '<span class="sys-tag">' + esc(n.kind) + '</span>' : '';
    var badge = unread > 0 ? '<div class="cr-meta"><span class="badge-num">' + unread + '</span></div>' : '';
    return '<div class="chat-row system pinned tappable" data-go="Z2" data-last-at="' + esc(n && n.createdAt ? n.createdAt : '') + '">'
      + '<div class="cr-av system"><i class="ti ti-bell"></i></div>'
      + '<div class="cr-bd"><div class="cr-top"><div class="cr-nm">系统通知 <span class="role">DUNES · SYS</span></div>'
      + '<div class="cr-tm">' + (n && n.createdAt ? esc(formatTime(n.createdAt)) : '') + '</div></div>'
      + '<div class="cr-pv">' + tag + pv + '</div></div>' + badge + '</div>';
  }
  function defaultAiRow(preview) {
    return convRow({
      id: 0,
      kind: 'AI_ASSISTANT',
      title: YUNSHU_NAME,
      lastMessagePreview: preview || YUNSHU_INTRO,
      unreadCount: 0,
      pinned: true,
      lastMessageAt: null
    });
  }
  function kbChatIconHtml() {
    return '<svg class="kb-chat-ic" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">'
      + '<path d="M5 4.5C5 3.67 5.67 3 6.5 3H11v18H6.5A1.5 1.5 0 0 1 5 19.5V4.5Z" fill="rgba(255,255,255,.92)"/>'
      + '<path d="M13 3h4.5c.83 0 1.5.67 1.5 1.5v15c0 .83-.67 1.5-1.5 1.5H13V3Z" fill="rgba(255,255,255,.72)"/>'
      + '<path d="M11 3v18" stroke="rgba(255,255,255,.32)" stroke-width=".8"/>'
      + '<path d="M17.2 5.4l.55 1.12 1.24.18-.9.88.21 1.23-1.1-.58-1.1.58.21-1.23-.9-.88 1.24-.18z" fill="#FFD580"/>'
      + '</svg>';
  }
  window.dunesKbIconHtml = kbChatIconHtml;
  window.dunesKbAvatarHtml = function (avClass) {
    return '<div class="' + (avClass || 'msg-av-sm kb-ai-av') + '">' + kbChatIconHtml() + '</div>';
  };
  function defaultKbChatRow() {
    var preview = window.__dunesKbPreviewHtml ? window.__dunesKbPreviewHtml() : '向知识库提问…';
    var at = '';
    try {
      at = sessionStorage.getItem('dunes_kb_last_preview_at') || localStorage.getItem('dunes_kb_last_preview_at') || '';
    } catch (e) {}
    var time = at ? formatTime(at) : '';
    return '<div class="chat-row pinned kb-chat-row tappable" data-kb-chat="1">'
      + '<div class="cr-av kb-chat">' + kbChatIconHtml() + '</div>'
      + '<div class="cr-bd"><div class="cr-top"><div class="cr-nm">知识库 <span class="ai-mark">AI</span></div>' + (time ? '<div class="cr-tm">' + esc(time) + '</div>' : '') + '</div>'
      + '<div class="cr-pv">' + preview + '</div></div></div>';
  }
  function defaultBroadcastRow(preview) {
    return convRow({
      id: 0,
      kind: 'BROADCAST',
      title: '公司广播',
      lastMessagePreview: preview || '暂无消息',
      unreadCount: 0,
      pinned: true,
      lastMessageAt: null
    });
  }
  function buildFixedSections(convs, notif, notifUnread, placeholders) {
    placeholders = placeholders || {};
    var ai = convs.filter(function (c) { return c.kind === 'AI_ASSISTANT'; });
    if (ai.length > 1) {
      ai.sort(function (a, b) {
        return new Date(b.lastMessageAt || 0).getTime() - new Date(a.lastMessageAt || 0).getTime();
      });
      ai = [ai[0]];
    }
    var broadcast = convs.filter(function (c) { return c.kind === 'BROADCAST'; });
    var aiRows = ai.length ? ai.map(convRow).join('') : defaultAiRow(placeholders.ai);
    var aiCnt = ai.length || 1;
    var pinRows = systemRow(notif, notifUnread);
    pinRows += broadcast.length ? broadcast.map(convRow).join('') : defaultBroadcastRow(placeholders.broadcast);
    var pinCnt = 1 + (broadcast.length || 1);
    var html = '';
    html += section('ti-sparkles', YUNSHU_NAME, aiCnt, aiRows, true, 'ai', maxConvTs(ai));
    var notifTs = notif && notif.createdAt ? new Date(notif.createdAt).getTime() : 0;
    if (isNaN(notifTs)) notifTs = 0;
    return {
      html: html,
      ai: ai,
      broadcast: broadcast,
      systemSection: {
        icon: 'ti-pin',
        label: '系统消息 · 公司广播',
        count: pinCnt,
        rows: pinRows,
        pin: true,
        key: 'system',
        ts: Math.max(notifTs, maxConvTs(broadcast))
      }
    };
  }
  function updateCommTabBadge(total) {
    var n = Number(total) || 0;
    window.__dunesCommUnread = n;
    document.querySelectorAll('.tab-bar .tab[data-go="C1"] .red-dot').forEach(function (dot) {
      if (n > 0) dot.classList.add('show');
      else dot.classList.remove('show');
    });
  }
  function parseEventPayload(data) {
    var payload = data && data.message ? data.message.payload : null;
    if (!payload) return {};
    if (typeof payload === 'object') return payload;
    try { return JSON.parse(payload); } catch (e) { return {}; }
  }
  function eventMentionsMe(data) {
    if (!data || !data.message) return false;
    var me = Number(localStorage.getItem('dunes_user_id') || '0');
    if (!me) return false;
    var payload = parseEventPayload(data);
    if (payload.mentionAll || payload.atAll || payload.isAtAll) return true;
    var lists = [payload.mentionUserIds, payload.mentionedUserIds, payload.atUserIds, payload.mentions];
    for (var i = 0; i < lists.length; i++) {
      var arr = lists[i];
      if (!arr) continue;
      if (!Array.isArray(arr)) arr = [arr];
      for (var j = 0; j < arr.length; j++) {
        var item = arr[j];
        var uid = Number(item && typeof item === 'object' ? (item.userId || item.id) : item);
        if (uid === me) return true;
      }
    }
    var body = String(data.message.bodyText || '');
    var mine = localStorage.getItem('dunes_display_name') || '';
    return body.indexOf('@所有人') >= 0 || (mine && body.indexOf('@' + mine) >= 0);
  }
  function rowMutedMark(row) {
    return row && row.querySelector('.cr-meta .muted') ? '<span class="muted"><i class="ti ti-volume-off"></i></span>' : '';
  }
  var _commBadgeRefreshTimer = null;
  function scheduleCommBadgeRefresh() {
    if (_commBadgeRefreshTimer) clearTimeout(_commBadgeRefreshTimer);
    _commBadgeRefreshTimer = setTimeout(function () {
      _commBadgeRefreshTimer = null;
      refreshCommBadgeFromServer();
    }, 350);
  }
  async function refreshCommBadgeFromServer() {
    try {
      var convJ = await apiFetch('/conversations');
      if (!convJ.success) return;
      var convs = convJ.data || [];
      var notifUnread = 0;
      try {
        var nJ = await apiFetch('/notifications');
        if (nJ.success && nJ.data) {
          notifUnread = nJ.data.unreadCount || 0;
          window.__dunesNotifUnread = notifUnread;
        }
      } catch (e) {}
      var list = document.getElementById('c1-conv-list');
      if (list && list.classList.contains('dunes-api-ready')) {
        convs.forEach(function (c) {
          if (!c.id) return;
          if (String(c.kind || '').toUpperCase() === 'AI_ASSISTANT') {
            refreshNovaInboxPreview();
          }
          list.querySelectorAll('.chat-row[data-conv-id="' + c.id + '"]').forEach(function (row) {
            var n = Number(c.unreadCount || 0);
            var meta = row.querySelector('.cr-meta');
            var mutedMark = rowMutedMark(row);
            if (n > 0) {
              if (!meta) {
                meta = document.createElement('div');
                meta.className = 'cr-meta';
                row.appendChild(meta);
              }
              meta.innerHTML = mutedMark + '<span class="badge-num accent">' + n + '</span>';
            } else if (meta) meta.innerHTML = mutedMark;
          });
        });
        var sysRow = list.querySelector('.chat-row.system[data-go="Z2"]');
        if (sysRow) {
          var sysMeta = sysRow.querySelector('.cr-meta');
          if (notifUnread > 0) {
            if (!sysMeta) {
              sysMeta = document.createElement('div');
              sysMeta.className = 'cr-meta';
              sysRow.appendChild(sysMeta);
            }
            sysMeta.innerHTML = '<span class="badge-num">' + notifUnread + '</span>';
          } else if (sysMeta) sysMeta.innerHTML = '';
        }
        recalcCommBadgeFromDom();
      } else {
        var total = notifUnread;
        convs.forEach(function (c) { total += Number(c.unreadCount || 0); });
        updateCommTabBadge(total);
      }
    } catch (e) { console.warn('refreshCommBadgeFromServer', e); }
  }
  function patchConvUnread(convId, count) {
    if (!convId) return;
    var list = document.getElementById('c1-conv-list');
    if (!list) return;
    var n = Number(count) || 0;
    list.querySelectorAll('.chat-row[data-conv-id="' + convId + '"]').forEach(function (row) {
      var meta = row.querySelector('.cr-meta');
      var mutedMark = rowMutedMark(row);
      if (!meta && n > 0) {
        meta = document.createElement('div');
        meta.className = 'cr-meta';
        row.appendChild(meta);
      }
      if (!meta) return;
      if (n > 0) meta.innerHTML = mutedMark + '<span class="badge-num accent">' + n + '</span>';
      else meta.innerHTML = mutedMark;
    });
    var convUnread = 0;
    list.querySelectorAll('.chat-row[data-conv-id] .badge-num').forEach(function (b) {
      convUnread += parseInt(b.textContent, 10) || 0;
    });
    updateCommTabBadge(convUnread + (window.__dunesNotifUnread || 0));
  }
  function recalcCommBadgeFromDom() {
    var list = document.getElementById('c1-conv-list');
    if (!list) return;
    var convUnread = 0;
    list.querySelectorAll('.chat-row[data-conv-id] .badge-num').forEach(function (b) {
      convUnread += parseInt(b.textContent, 10) || 0;
    });
    var sysBadge = list.querySelector('.chat-row.system .badge-num');
    var notifUnread = sysBadge
      ? (parseInt(sysBadge.textContent, 10) || 0)
      : (window.__dunesNotifUnread || 0);
    updateCommTabBadge(convUnread + notifUnread);
  }
  var _convUnreadSync = {};
  function scheduleConvUnreadSync(convId) {
    var k = String(convId);
    if (_convUnreadSync[k]) clearTimeout(_convUnreadSync[k]);
    _convUnreadSync[k] = setTimeout(function () {
      delete _convUnreadSync[k];
      apiFetch('/conversations').then(function (j) {
        if (!j.success || !j.data) return;
        var c = (j.data || []).find(function (x) { return String(x.id) === k; });
        if (c) patchConvUnread(convId, c.unreadCount || 0);
      }).catch(function () {});
    }, 350);
  }
  function notiCardHtml(n) {
    var unread = n.unread || !n.readAt;
    var cls = 'noti-card noti-card-static' + (unread ? ' urgent' : '');
    var kind = n.kind || '系统';
    var time = n.createdAt ? formatTimeDetailed(n.createdAt, true) : '';
    return '<div class="' + cls + '" data-noti-id="' + (n.id || '') + '">'
      + '<span class="nc-dot"></span><div class="nc-ic"><i class="ti ti-bell"></i></div>'
      + '<div class="nc-body"><div class="nc-top"><div class="nc-title">' + esc(n.title || '')
      + '</div><div class="nc-time">' + esc(time) + '</div></div>'
      + '<div class="nc-desc">' + formatBodyHtml(n.body || '') + '</div>'
      + '<span class="nc-tag biz">' + esc(kind) + '</span></div></div>';
  }
  async function refreshSystemNotifRow() {
    try {
      var nJ = await apiFetch('/notifications');
      if (!nJ.success || !nJ.data) return;
      var notifUnread = nJ.data.unreadCount || 0;
      window.__dunesNotifUnread = notifUnread;
      var items = nJ.data.items || [];
      var notif = items.length ? items[0] : null;
      var list = document.getElementById('c1-conv-list');
      if (!list || !list.classList.contains('dunes-api-ready')) {
        scheduleCommBadgeRefresh();
        return;
      }
      var row = list.querySelector('.chat-row.system[data-go="Z2"]');
      if (!row) return;
      var pv = row.querySelector('.cr-pv');
      var tm = row.querySelector('.cr-tm');
      if (pv) {
        var tag = notif && notif.kind ? '<span class="sys-tag">' + esc(notif.kind) + '</span>' : '';
        var bodyHtml = notif && notif.body ? formatBodyHtml(notif.body) : '';
        var text = notif
          ? esc(notif.title || '') + (bodyHtml ? '<br>' + bodyHtml : '')
          : '暂无新通知';
        pv.innerHTML = tag + text;
      }
      if (tm) tm.textContent = notif && notif.createdAt ? formatTime(notif.createdAt) : '';
      if (notif && notif.createdAt) row.setAttribute('data-last-at', notif.createdAt);
      var meta = row.querySelector('.cr-meta');
      if (notifUnread > 0) {
        if (!meta) {
          meta = document.createElement('div');
          meta.className = 'cr-meta';
          row.appendChild(meta);
        }
        meta.innerHTML = '<span class="badge-num">' + notifUnread + '</span>';
      } else if (meta) meta.innerHTML = '';
      recalcCommBadgeFromDom();
      reorderC1Sections();
    } catch (e) { console.warn('refreshSystemNotifRow', e); }
  }
  async function markBroadcastRead(convId) {
    if (!convId) return false;
    try {
      var j = await apiFetch('/conversations/' + convId + '/read', { method: 'POST' });
      if (!j || !j.success) {
        console.warn('markBroadcastRead failed', j && j.message);
        return false;
      }
      patchConvUnread(convId, 0);
      return true;
    } catch (e) {
      console.warn('markBroadcastRead', e);
      return false;
    }
  }
  async function markAllBroadcastsRead() {
    try {
      var j = await apiFetch('/conversations?kind=BROADCAST');
      if (!j.success || !j.data) return;
      var rows = j.data || [];
      for (var i = 0; i < rows.length; i++) {
        if (rows[i].id) await markBroadcastRead(rows[i].id);
      }
      recalcCommBadgeFromDom();
    } catch (e) {
      console.warn('markAllBroadcastsRead', e);
    }
  }
  var _c10State = { convId: 0, hasMore: false, loading: false, oldestId: 0, title: '公司广播' };
  function broadcastCardHtml(msg, channelTitle) {
    var time = msg.createdAt ? formatTimeDetailed(msg.createdAt, true) : '';
    var body = msg.recalled ? '消息已撤回' : (msg.bodyText || '');
    return '<div class="noti-card noti-card-static broadcast-msg-card" data-msg-id="' + (msg.id || '') + '">'
      + '<div class="nc-ic"><i class="ti ti-speakerphone"></i></div>'
      + '<div class="nc-body"><div class="nc-top"><div class="nc-title">' + esc(channelTitle || '公司广播')
      + '</div><div class="nc-time">' + esc(time) + '</div></div>'
      + '<div class="nc-desc">' + formatBodyHtml(body) + '</div></div></div>';
  }
  function updateC10Header(title) {
    var screen = document.querySelector('.screen[data-screen="C10"]');
    if (!screen) return;
    var crumb = screen.querySelector('.ds-crumb');
    var name = screen.querySelector('.ds-name');
    var short = String(title || '广播').replace(/^公司广播\s*[·•]\s*/, '');
    if (crumb) crumb.textContent = '公司广播 · ' + short;
    if (name) name.textContent = '广播历史';
  }
  async function resolveBroadcastConvId() {
    var cid = Number(window.pendingConvId || 0);
    if (cid > 0) return cid;
    try {
      var pending = typeof pendingConvId !== 'undefined' ? Number(pendingConvId) : 0;
      if (pending > 0) return pending;
    } catch (e) {}
    var j = await apiFetch('/conversations?kind=BROADCAST');
    if (j.success && j.data && j.data.length) return Number(j.data[0].id) || 0;
    return 0;
  }
  function ensureC10ScrollWired() {
    var box = document.getElementById('c10-api-rows');
    if (!box || box.dataset.c10ScrollWired) return;
    box.dataset.c10ScrollWired = '1';
    var content = box.closest('.content') || box.parentElement;
    if (!content) return;
    content.addEventListener('scroll', function () {
      if (_c10State.loading || !_c10State.hasMore) return;
      if (content.scrollTop + content.clientHeight < content.scrollHeight - 72) return;
      loadBroadcastMore();
    }, { passive: true });
  }
  function setC10LoadHint(text, show) {
    var hint = document.getElementById('c10-load-more');
    if (!hint) return;
    hint.innerHTML = text || '';
    hint.style.display = show ? '' : 'none';
  }
  async function loadBroadcastMore() {
    var box = document.getElementById('c10-api-rows');
    if (!box || _c10State.loading || !_c10State.hasMore || !_c10State.convId || !_c10State.oldestId) return;
    _c10State.loading = true;
    setC10LoadHint('<i class="ti ti-loader"></i><span>加载更早广播…</span>', true);
    try {
      var mj = await apiFetch('/conversations/' + _c10State.convId + '/messages?size=20&before=' + _c10State.oldestId);
      if (!mj.success || !mj.data) return;
      var items = mj.data.items || [];
      if (!items.length) {
        _c10State.hasMore = false;
        setC10LoadHint('', false);
        return;
      }
      items.sort(function (a, b) { return Number(a.id) - Number(b.id); });
      _c10State.oldestId = Number(items[0].id) || _c10State.oldestId;
      _c10State.hasMore = !!mj.data.hasMore;
      box.insertAdjacentHTML('beforeend', items.map(function (m) {
        return broadcastCardHtml(m, _c10State.title);
      }).join(''));
      if (!_c10State.hasMore) setC10LoadHint('', false);
      else setC10LoadHint('<i class="ti ti-chevron-down"></i><span>上滑加载更早</span>', true);
    } catch (e) {
      console.warn('loadBroadcastMore', e);
      setC10LoadHint('<span>加载失败</span>', true);
    } finally {
      _c10State.loading = false;
    }
  }
  async function loadBroadcastList() {
    var box = document.getElementById('c10-api-rows');
    if (!box) return;
    _c10State.loading = true;
    _c10State.hasMore = false;
    _c10State.oldestId = 0;
    box.innerHTML = '<div class="api-strip"><i class="ti ti-loader"></i><span>加载广播…</span></div>';
    setC10LoadHint('', false);
    try {
      var convId = await resolveBroadcastConvId();
      if (!convId) {
        box.innerHTML = '<div class="api-strip"><i class="ti ti-info-circle"></i><span>暂无广播频道</span></div>';
        return;
      }
      _c10State.convId = convId;
      window.pendingConvId = convId;
      try { pendingConvId = convId; } catch (e) {}
      await markBroadcastRead(convId);
      var title = '公司广播';
      try {
        var dj = await apiFetch('/conversations/' + convId);
        if (dj.success && dj.data && dj.data.title) title = dj.data.title;
      } catch (e) {}
      _c10State.title = title;
      updateC10Header(title);
      var mj = await apiFetch('/conversations/' + convId + '/messages?size=20');
      if (!mj.success) throw new Error(mj.message || 'messages failed');
      var items = (mj.data && mj.data.items) || [];
      if (!items.length) {
        box.innerHTML = '<div class="api-strip"><i class="ti ti-info-circle"></i><span>暂无广播消息</span></div>';
        return;
      }
      items.sort(function (a, b) { return Number(b.id) - Number(a.id); });
      _c10State.oldestId = Number(items[items.length - 1].id) || 0;
      _c10State.hasMore = !!(mj.data && mj.data.hasMore);
      box.innerHTML = items.map(function (m) { return broadcastCardHtml(m, title); }).join('');
      if (_c10State.hasMore) setC10LoadHint('<i class="ti ti-chevron-down"></i><span>上滑加载更早</span>', true);
      ensureC10ScrollWired();
    } catch (e) {
      box.innerHTML = '<div class="api-strip"><span>' + esc(String(e.message || e)) + '</span></div>';
      console.warn('loadBroadcastList', e);
    } finally {
      _c10State.loading = false;
    }
  }
  async function markAllNotificationsRead() {
    try {
      var j = await apiFetch('/notifications/read-all', { method: 'POST' });
      if (j.success) {
        window.__dunesNotifUnread = 0;
        refreshSystemNotifRow();
        recalcCommBadgeFromDom();
      }
    } catch (e) {
      console.warn('markAllNotificationsRead', e);
    }
  }
  async function loadZ2Notifications() {
    var box = document.getElementById('z2-api-rows');
    var badge = document.getElementById('z2-unread-badge');
    var root = document.getElementById('z2-noti-list');
    if (!box) return;
    try {
      var j = await apiFetch('/notifications');
      if (!j.success) throw new Error(j.message || 'notifications failed');
      var data = j.data || {};
      var rows = data.items || [];
      var unread = data.unreadCount || 0;
      window.__dunesNotifUnread = unread;
      if (badge) badge.textContent = unread + ' 未读';
      box.innerHTML = rows.length
        ? rows.map(notiCardHtml).join('')
        : '<div class="api-strip"><i class="ti ti-info-circle"></i><span>暂无通知</span></div>';
      if (root) root.classList.add('z2-api-ready');
      refreshSystemNotifRow();
    } catch (e) {
      box.innerHTML = '<div class="api-strip"><span>' + esc(String(e.message || e)) + '</span></div>';
      if (root) root.classList.remove('z2-api-ready');
      console.warn('loadZ2Notifications', e);
    }
  }
  function devUserId() {
    try {
      var t = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
      if (t) {
        var p = JSON.parse(atob(t.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
        if (p.userId != null) {
          var n = Number(p.userId);
          if (!isNaN(n) && n > 0) return n;
        }
        if (p.sub) {
          var s = parseInt(String(p.sub), 10);
          if (!isNaN(s) && s > 0) return s;
        }
      }
    } catch (e) {}
    var uid = parseInt(localStorage.getItem('dunes_user_id') || '0', 10);
    return isNaN(uid) ? 0 : uid;
  }
  function refreshC1OnlineDots() {
    var online = window.__dunesOnlineUserIds || {};
    document.querySelectorAll('#c1-conv-list .chat-row[data-peer-user-id]').forEach(function (row) {
      var dot = row.querySelector('.av-dot');
      if (!dot) return;
      var pid = Number(row.getAttribute('data-peer-user-id'));
      if (pid && online[String(pid)]) dot.classList.add('on');
      else dot.classList.remove('on');
    });
  }
  function wireC1RowActions(root) {
    if (!root) return;
    root.querySelectorAll('.chat-row[data-peer-user-id]').forEach(function (row) {
      var av = row.querySelector('.cr-av[data-open-contact]');
      if (!av || av.dataset.wiredC9) return;
      av.dataset.wiredC9 = '1';
      av.style.cursor = 'pointer';
      av.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        var uid = Number(row.getAttribute('data-peer-user-id'));
        if (!uid) return;
        window.pendingContactUserId = uid;
        if (typeof go === 'function') go('C9');
      });
    });
    root.querySelectorAll('.chat-row[data-go="C5"]').forEach(function (row) {
      if (row.dataset.wiredC5) return;
      row.dataset.wiredC5 = '1';
      row.addEventListener('click', function () {
        var uid = Number(row.getAttribute('data-peer-user-id'));
        var cid = Number(row.getAttribute('data-conv-id'));
        if (typeof window.__dunesSelectConversation === 'function') {
          window.__dunesSelectConversation(cid, uid);
        } else {
          if (cid) {
            window.pendingConvId = cid;
            try { pendingConvId = cid; } catch (e) {}
          }
          if (uid) {
            window.pendingContactUserId = uid;
            window.__dunesPendingPeerUserId = uid;
            try { pendingContactUserId = uid; } catch (e) {}
          }
        }
      }, true);
    });
    root.querySelectorAll('.chat-row.broadcast[data-conv-id]').forEach(function (row) {
      if (row.dataset.wiredBroadcast) return;
      row.dataset.wiredBroadcast = '1';
      row.addEventListener('click', function () {
        var cid = Number(row.getAttribute('data-conv-id'));
        if (cid) {
          window.pendingConvId = cid;
          try { pendingConvId = cid; } catch (e) {}
          markBroadcastRead(cid);
        }
      }, true);
    });
    if (!root || root.dataset.c1ClickDelegated) return;
    root.dataset.c1ClickDelegated = '1';
    root.addEventListener('click', function (e) {
      var row = e.target.closest('.chat-row.broadcast[data-conv-id]');
      if (!row) return;
      var cid = Number(row.getAttribute('data-conv-id'));
      if (cid) markBroadcastRead(cid);
    }, true);
  }
  function wireC1Search() {
    if (searchWired) return;
    var inp = document.querySelector('.screen[data-screen="C1"] .chat-search input');
    if (!inp) return;
    searchWired = true;
    inp.addEventListener('input', function () {
      var q = inp.value.trim().toLowerCase();
      var list = document.getElementById('c1-conv-list');
      if (!list) return;
      list.querySelectorAll('.c1-swipe-item').forEach(function (wrap) {
        var row = wrap.querySelector('.chat-row');
        var hit = !q || (row && (row.textContent || '').toLowerCase().indexOf(q) >= 0);
        wrap.style.display = hit ? '' : 'none';
      });
      list.querySelectorAll('.chat-row').forEach(function (row) {
        if (row.closest('.c1-swipe-item')) return;
        var hit = !q || (row.textContent || '').toLowerCase().indexOf(q) >= 0;
        row.style.display = hit ? '' : 'none';
      });
    });
  }
  function ensureC1ScrollWired() {
    var c = c1ContentEl();
    if (!c || c.dataset.dunesC1ScrollWired) return;
    c.dataset.dunesC1ScrollWired = '1';
    c.addEventListener('scroll', rememberC1Scroll, { passive: true });
  }
  function scheduleC1Refresh() {
    if (_c1RefreshTimer) clearTimeout(_c1RefreshTimer);
    _c1RefreshTimer = setTimeout(function () {
      _c1RefreshTimer = null;
      var active = document.querySelector('.screen.active');
      if (active && active.dataset.screen === 'C1') loadC1();
    }, 400);
  }
  function renderDynamicSections(sections) {
    return (sections || [])
      .filter(function (s) { return s && s.rows; })
      .sort(function (a, b) { return (b.ts || 0) - (a.ts || 0); })
      .map(function (s) {
        return section(s.icon, s.label, s.count, s.rows, s.pin, s.key, s.ts);
      }).join('');
  }
  function sectionBlock(header) {
    var nodes = [];
    if (!header || !header.parentNode) return nodes;
    nodes.push(header);
    var n = header.nextSibling;
    while (n) {
      if (n.nodeType === 1 && n.classList && n.classList.contains('chat-section')) break;
      nodes.push(n);
      n = n.nextSibling;
    }
    return nodes;
  }
  function sectionTimestamp(header) {
    if (!header) return 0;
    var max = Number(header.getAttribute('data-section-ts') || 0) || 0;
    var n = header.nextElementSibling;
    while (n && !(n.classList && n.classList.contains('chat-section'))) {
      if (n.classList && n.classList.contains('c1-swipe-item')) {
        var inner = n.querySelector('.chat-row[data-last-at]');
        if (inner) {
          var rawInner = inner.getAttribute('data-last-at') || '';
          var tInner = rawInner ? new Date(rawInner).getTime() : 0;
          if (!isNaN(tInner) && tInner > max) max = tInner;
        }
      } else if (n.classList && n.classList.contains('chat-row')) {
        var raw = n.getAttribute('data-last-at') || '';
        var t = raw ? new Date(raw).getTime() : 0;
        if (!isNaN(t) && t > max) max = t;
      }
      n = n.nextElementSibling;
    }
    header.setAttribute('data-section-ts', String(max || 0));
    return max || 0;
  }
  function reorderC1Sections() {
    var list = document.getElementById('c1-conv-list');
    if (!list) return;
    var ai = list.querySelector('.chat-section[data-section-key="ai"]');
    var anchor = ai ? sectionBlock(ai).slice(-1)[0] : null;
    var headers = Array.from(list.querySelectorAll('.chat-section[data-section-key]'))
      .filter(function (h) { return h.getAttribute('data-section-key') !== 'ai'; });
    headers.sort(function (a, b) { return sectionTimestamp(b) - sectionTimestamp(a); });
    headers.forEach(function (h) {
      var block = sectionBlock(h);
      block.forEach(function (node) {
        list.insertBefore(node, anchor ? anchor.nextSibling : list.firstChild);
        anchor = node;
      });
    });
  }
  function moveConvRowToTop(row) {
    if (!row || !row.parentNode) return;
    var target = row.closest ? row.closest('.c1-swipe-item') : null;
    if (!target) target = row;
    var el = target.previousElementSibling;
    var section = null;
    while (el) {
      if (el.classList && el.classList.contains('chat-section')) {
        section = el;
        break;
      }
      el = el.previousElementSibling;
    }
    if (!section || section.nextElementSibling === target) return;
    target.parentNode.insertBefore(target, section.nextElementSibling);
  }
  function applyConvEvent(data) {
    if (!data || !data.conversationId) return;
    var convId = data.conversationId;
    var me = Number(localStorage.getItem('dunes_user_id') || '0');
    if (data.type === 'read') {
      if (Number(data.userId || 0) === me && typeof scheduleConvUnreadSync === 'function') {
        scheduleConvUnreadSync(convId);
      }
      return;
    }
    var senderId = data.message
      ? Number((data.message.sender && data.message.sender.userId) || data.message.senderUserId || 0)
      : 0;
    var fromPeer = !!(data.message && senderId && senderId !== me);
    var activeScreen = document.querySelector('.screen.active')?.dataset?.screen || '';
    var novaConvId = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
    var isNovaAiMsg = data.message && (
      String(data.message.kind || '').indexOf('AI') >= 0
      || (data.message.sender && (!data.message.sender.userId || data.message.sender.displayName === '云枢' || data.message.sender.displayName === 'NOVA'))
    );
    var viewingNova = activeScreen === 'C4' && novaConvId > 0 && novaConvId === Number(convId);
    var bumpUnread = (fromPeer && (data.type === 'message' || data.type === 'system_flow'))
      || (isNovaAiMsg && !viewingNova && data.type === 'message');
    var mentionHit = eventMentionsMe(data);
    if (mentionHit && activeScreen !== 'C2') bumpUnread = true;
    var list = document.getElementById('c1-conv-list');
    if (!list || !list.classList.contains('dunes-api-ready')) {
      if (isConvHidden(convId)) {
        if (shouldUnhideFromEvent(data)) {
          unhideConvLocally(convId);
          scheduleC1Refresh();
        }
        return;
      }
      if (bumpUnread || data.type === 'conversation_updated' || data.type === 'notification') scheduleCommBadgeRefresh();
      if (mentionHit && bumpUnread) updateCommTabBadge((window.__dunesCommUnread || 0) + 1);
      if (data.type === 'conversation_updated') scheduleC1Refresh();
      else if (!bumpUnread) scheduleC1Refresh();
      return;
    }
    if (isConvHidden(convId)) {
      if (shouldUnhideFromEvent(data)) {
        unhideConvLocally(convId);
        scheduleC1Refresh();
      }
      return;
    }
    var row = findC1ConvRow(list, convId);
    if (!row) {
      if (bumpUnread) scheduleCommBadgeRefresh();
      scheduleC1Refresh();
      return;
    }
    var preview = '';
    var at = null;
    var isGroupRow = row.getAttribute('data-go') === 'C2' || row.classList.contains('workgroup-approval');
    if (data.type === 'message' && data.message) {
      preview = eventPreviewText(data, { group: isGroupRow, row: row });
      if (isGroupRow) {
        var msgSender = (data.message.sender && data.message.sender.displayName)
          || data.message.senderDisplayName || '';
        if (!msgSender) {
          var msgSid = Number((data.message.sender && data.message.sender.userId) || data.message.senderUserId || 0);
          var meId = Number(localStorage.getItem('dunes_user_id') || '0');
          if (msgSid && msgSid === meId) msgSender = localStorage.getItem('dunes_display_name') || '';
        }
        if (msgSender) cacheConvPreviewSender(convId, msgSender, data.message.kind, data.message.bodyText, data.message.createdAt);
      }
      at = data.message.createdAt;
    } else if (data.type === 'message_recalled') {
      preview = (data.preview == null || data.preview === '') ? '消息已撤回' : String(data.preview);
      if (isGroupRow) {
        var recallName = data.recalledByName || data.recalledByDisplayName || '';
        if (!recallName && data.userId) {
          var rp = typeof profileForUserId === 'function' ? profileForUserId(Number(data.userId)) : null;
          if (rp && rp.displayName) recallName = rp.displayName;
        }
        if (recallName) preview = recallName + ': ' + preview;
      }
      at = data.previewAt || null;
    } else if (data.type === 'message_updated' && data.message) {
      preview = eventPreviewText(data, { group: isGroupRow, row: row });
      at = data.message.createdAt;
    } else if (data.type === 'message_deleted') {
      preview = '消息已删除';
    } else if (data.type === 'system_flow' && data.message) {
      preview = data.message.bodyText || '[系统]';
      at = data.message.createdAt;
    } else if (data.type === 'conversation_updated') {
      preview = eventPreviewText(data, { group: isGroupRow, row: row });
      at = data.updatedAt || data.lastMessageAt || null;
      if (row.classList.contains('broadcast') && activeScreen !== 'C10') bumpUnread = true;
    }
    if (preview) {
      var pv = row.querySelector('.cr-pv');
      if (pv) {
        if (row.classList.contains('nova-generating')) {
          if (isNovaAiMsg) {
            row.classList.remove('nova-generating');
            delete row.dataset.previewNormal;
            pv.textContent = preview;
          }
        } else {
          pv.textContent = preview;
        }
      }
    }
    if (at) {
      var tm = row.querySelector('.cr-tm');
      if (tm) tm.textContent = formatTimeDetailed(at, true);
      row.setAttribute('data-last-at', at);
    }
    moveConvRowToTop(row);
    reorderC1Sections();
    if (bumpUnread) {
      if (mentionHit) {
        var cur = 0;
        var badge = row.querySelector('.badge-num');
        if (badge) cur = parseInt(badge.textContent, 10) || 0;
        patchConvUnread(convId, Math.max(cur + 1, 1));
      } else {
        var curUnread = 0;
        var unreadBadge = row.querySelector('.badge-num');
        if (unreadBadge) curUnread = parseInt(unreadBadge.textContent, 10) || 0;
        patchConvUnread(convId, Math.max(curUnread + 1, 1));
        scheduleConvUnreadSync(convId);
      }
    }
  }
  async function loadC1() {
    var list = document.getElementById('c1-conv-list');
    var sub = document.querySelector('.screen[data-screen="C1"] .ch-t .sub');
    if (!list) return;
    if (window.DunesScreenLoader) window.DunesScreenLoader.show('C1', '加载通讯…');
    list.classList.remove('dunes-api-ready');
    list.innerHTML = '';
    try {
      var convJ = await apiFetch('/conversations');
      if (!convJ.success) throw new Error(convJ.message || 'conversations failed');
      var convs = convJ.data || [];
      upgradeDissolvedHiddenConvs(convs);
      purgeDissolvedConvsFromServer(convs);
      var notif = null;
      var notifUnread = 0;
      try {
        var nJ = await apiFetch('/notifications');
        if (nJ.success && nJ.data) {
          notifUnread = nJ.data.unreadCount || 0;
          window.__dunesNotifUnread = notifUnread;
          var items = nJ.data.items || [];
          if (items.length) notif = items[0];
        }
      } catch (e) {}
      var approval = sortConvList(filterVisibleConvs(convs.filter(function (c) { return c.kind === 'WORKGROUP_APPROVAL'; })));
      var groups = sortConvList(filterVisibleConvs(convs.filter(function (c) {
        return c.kind === 'WORKGROUP' || c.kind === 'GROUP';
      })));
      var priv = filterVisibleConvs(convs.filter(function (c) { return c.kind === 'PRIVATE'; }));
      var visibleCount = approval.length + groups.length + priv.length;
      if (sub) sub.textContent = 'CHAT · ' + visibleCount;
      var fixed = buildFixedSections(convs, notif, notifUnread);
      var html = fixed.html + renderDynamicSections([
        fixed.systemSection,
        approval.length ? {
          icon: 'ti-route',
          label: '审批工作群 · 系统自动建群',
          count: approval.length,
          rows: approval.map(convRow).join(''),
          pin: true,
          key: 'approval',
          ts: maxConvTs(approval)
        } : null,
        groups.length ? {
          icon: 'ti-users',
          label: '工作群',
          count: groups.length,
          rows: groups.map(convRow).join(''),
          pin: false,
          key: 'group',
          ts: maxConvTs(groups)
        } : null,
        priv.length ? {
          icon: 'ti-message',
          label: '1 对 1',
          count: priv.length,
          rows: priv.map(privateConvRow).join(''),
          pin: false,
          key: 'private',
          ts: maxConvTs(priv)
        } : null
      ]);
      list.innerHTML = html;
      list.classList.add('dunes-api-ready');
      ensureC1ScrollWired();
      wireC1Search();
      wireC1RowActions(list);
      wireC1SwipeDelete(list);
      hydrateAvatarsIn(list);
      if (window.DunesPresence && typeof window.DunesPresence.refreshAll === 'function') {
        window.DunesPresence.refreshAll();
      } else {
        refreshC1OnlineDots();
      }
      var unreadTotal = notifUnread;
      convs.forEach(function (c) { unreadTotal += Number(c.unreadCount || 0); });
      updateCommTabBadge(unreadTotal);
      if (window.DunesApi && typeof window.DunesApi.connectImWs === 'function') {
        window.DunesApi.connectImWs();
      }
      _c1Loaded = true;
      restoreC1Scroll();
      if (window.DunesKbChat && typeof window.DunesKbChat.refreshKbInboxPreview === 'function') {
        window.DunesKbChat.refreshKbInboxPreview(true);
      }
      if (window.DunesNovaChat && typeof window.DunesNovaChat.prefetchServerHistory === 'function') {
        window.DunesNovaChat.prefetchServerHistory().then(function () {
          refreshNovaInboxPreview();
        }).catch(function () {
          refreshNovaInboxPreview();
        });
      } else {
        refreshNovaInboxPreview();
      }
    } catch (e) {
      var errPreview = '消息列表加载失败：' + (e.message || e);
      var fallback = buildFixedSections([], null, 0);
      var errHtml = fallback.html;
      errHtml += section('ti-route', '审批工作群 · 系统自动建群', 0, '', true);
      errHtml += '<div class="api-strip"><span>' + esc(errPreview) + '</span></div>';
      list.innerHTML = errHtml;
      list.classList.add('dunes-api-ready');
      console.warn('DunesInbox.loadC1', e);
    } finally {
      if (window.DunesScreenLoader) window.DunesScreenLoader.hide('C1');
    }
  }
  function onScreen(id) {
    if (id === 'C1') {
      ensureC1ScrollWired();
      if (_c1Loaded && window.__dunesRefreshC1OnNextShow) {
        window.__dunesRefreshC1OnNextShow = false;
        loadC1();
      } else if (_c1Loaded) {
        restoreC1Scroll();
        refreshNovaInboxPreview();
        if (window.DunesNovaChat && typeof window.DunesNovaChat.prefetchServerHistory === 'function') {
          window.DunesNovaChat.prefetchServerHistory().then(function () {
            refreshNovaInboxPreview();
          }).catch(function () {
            refreshNovaInboxPreview();
          });
        }
      } else loadC1();
    }
    if (id === 'Z2') {
      markAllNotificationsRead().then(function () { loadZ2Notifications(); });
    }
    if (id === 'C10') {
      window.__dunesRefreshC1OnNextShow = true;
      loadBroadcastList();
    }
  }
  return {
    onScreen: onScreen,
    loadC1: loadC1,
    loadZ2Notifications: loadZ2Notifications,
    loadBroadcastList: loadBroadcastList,
    markBroadcastRead: markBroadcastRead,
    markAllBroadcastsRead: markAllBroadcastsRead,
    markAllNotificationsRead: markAllNotificationsRead,
    refreshSystemNotifRow: refreshSystemNotifRow,
    applyConvEvent: applyConvEvent,
    refreshC1OnlineDots: refreshC1OnlineDots,
    updateCommTabBadge: updateCommTabBadge,
    patchConvUnread: patchConvUnread,
    patchNovaGeneratingPreview: patchNovaGeneratingPreview,
    refreshNovaInboxPreview: refreshNovaInboxPreview,
    recalcCommBadgeFromDom: recalcCommBadgeFromDom,
    refreshCommBadgeFromServer: refreshCommBadgeFromServer,
    scheduleCommBadgeRefresh: scheduleCommBadgeRefresh,
    finishExitGroup: finishExitGroup,
    hideConvLocally: hideConvLocally,
    exitGroupMembership: exitGroupMembership
  };
})();
''';

  static const _dialogJs = r'''
window.DunesDialog = (function () {
  var pending = null;
  function ensureRoot() {
    var root = document.getElementById('dunes-dialog-root');
    if (root) return root;
    root = document.createElement('div');
    root.id = 'dunes-dialog-root';
    root.innerHTML = '<div class="dunes-dialog-card" role="dialog" aria-modal="true">'
      + '<div class="dunes-dialog-body"><div id="dunes-dialog-msg"></div>'
      + '<input id="dunes-dialog-input" class="dunes-dialog-input" type="text" style="display:none"></div>'
      + '<div class="dunes-dialog-actions">'
      + '<button type="button" class="cancel" id="dunes-dialog-cancel">取消</button>'
      + '<button type="button" class="ok" id="dunes-dialog-ok">确定</button>'
      + '</div></div>';
    document.body.appendChild(root);
    root.querySelector('#dunes-dialog-cancel').addEventListener('click', function () {
      finish(false);
    });
    root.querySelector('#dunes-dialog-ok').addEventListener('click', function () {
      if (pending && pending.mode === 'prompt') {
        var inp = document.getElementById('dunes-dialog-input');
        finish(true, inp ? inp.value : '');
        return;
      }
      finish(true);
    });
    root.addEventListener('click', function (e) {
      if (e.target === root) finish(false);
    });
    return root;
  }
  function finish(ok, value) {
    var root = document.getElementById('dunes-dialog-root');
    if (root) root.classList.remove('show');
    var cb = pending;
    pending = null;
    if (!cb) return;
    if (cb.mode === 'prompt') cb.resolve(ok ? (value == null ? '' : String(value)) : null);
    else cb.resolve(!!ok);
  }
  function show(message, mode, defaultValue) {
    ensureRoot();
    pending = { mode: mode, resolve: null };
    return new Promise(function (resolve) {
      pending.resolve = resolve;
      var root = document.getElementById('dunes-dialog-root');
      var msg = document.getElementById('dunes-dialog-msg');
      var inp = document.getElementById('dunes-dialog-input');
      var cancelBtn = document.getElementById('dunes-dialog-cancel');
      if (msg) msg.textContent = message || '';
      if (inp) {
        if (mode === 'prompt') {
          inp.style.display = 'block';
          inp.value = defaultValue == null ? '' : String(defaultValue);
          setTimeout(function () { inp.focus(); inp.select(); }, 50);
        } else {
          inp.style.display = 'none';
          inp.value = '';
        }
      }
      if (cancelBtn) cancelBtn.style.display = mode === 'alert' ? 'none' : '';
      root.classList.add('show');
    });
  }
  function confirm(message) { return show(message, 'confirm'); }
  function prompt(message, defaultValue) { return show(message, 'prompt', defaultValue); }
  function alert(message) { return show(message, 'alert').then(function () {}); }
  return { confirm: confirm, prompt: prompt, alert: alert };
})();
''';

  static const _groupInfoJs = r'''
window.DunesGroupInfo = (function () {
  var pickState = null;
  function devUserId() {
    return parseInt(localStorage.getItem('dunes_user_id') || '7', 10) || 7;
  }
  function esc(s) {
    return String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
  }
  function personCls(uid) {
    var n = Math.abs(Number(uid) || 0) % 6;
    return 'person-' + ['a', 'b', 'c', 'd', 'e', 'f'][n];
  }
  function currentConvId() {
    var id = Number(window.pendingConvId || 0);
    if (id > 0) return id;
    try { id = Number(pendingConvId || 0); } catch (e) {}
    return id > 0 ? id : 0;
  }
  function apiFetch(path, opts) {
    opts = opts || {};
    var base = localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var headers = Object.assign({}, opts.headers || {});
    if (token) headers.Authorization = 'Bearer ' + token;
    if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    return fetch(base + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body || undefined
    }).then(function (r) {
      if (r.status === 401 && typeof window.__dunesHandleSessionRevoked === 'function') {
        window.__dunesHandleSessionRevoked();
        return { success: false, message: '账号已在其他设备登录，请重新登录' };
      }
      return r.json();
    });
  }
  function toast(msg) {
    if (window.DunesAPI && window.DunesAPI.toast) window.DunesAPI.toast(msg);
    else if (window.DunesDialog && window.DunesDialog.alert) window.DunesDialog.alert(msg);
    else alert(msg);
  }
  function dlgConfirm(msg) {
    if (window.DunesDialog && window.DunesDialog.confirm) return window.DunesDialog.confirm(msg);
    if (window.dunesConfirm) return window.dunesConfirm(msg);
    return Promise.resolve(confirm(msg));
  }
  function dlgPrompt(msg, def) {
    if (window.DunesDialog && window.DunesDialog.prompt) return window.DunesDialog.prompt(msg, def);
    return Promise.resolve(prompt(msg, def));
  }
  function parsePayload(raw) {
    if (!raw) return {};
    if (typeof raw === 'object') return raw;
    try { return JSON.parse(raw); } catch (e) { return {}; }
  }
  function storageGetEndpoint(objectKey, bucket) {
    if (!objectKey) return '';
    var base = localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
    return base + '/storage/presigned-get?bucket=' + encodeURIComponent(bucket || 'im-attachments') + '&objectKey=' + encodeURIComponent(objectKey);
  }
  function storageDownloadEndpoint(objectKey, bucket, fileName) {
    if (!objectKey) return '';
    var base = localStorage.getItem('dunes_api_base') || '__DUNES_API_BASE__';
    var q = 'bucket=' + encodeURIComponent(bucket || 'im-attachments') + '&objectKey=' + encodeURIComponent(objectKey);
    if (fileName) q += '&fileName=' + encodeURIComponent(fileName);
    return base + '/storage/download?' + q;
  }
  async function resolveMediaUrl(objectKey, bucket) {
    if (!objectKey) return '';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var r = await fetch(storageGetEndpoint(objectKey, bucket || 'im-attachments'), {
      headers: token ? { Authorization: 'Bearer ' + token } : {}
    });
    var j = await r.json();
    return j && j.success && j.data && j.data.url ? j.data.url : '';
  }
  async function downloadMediaItem(item) {
    var payload = parsePayload(item.payload);
    var objectKey = String(payload.objectKey || payload.object_key || '').trim();
    var url = String(payload.url || payload.previewUrl || '').trim();
    if (!objectKey && url && !/^https?:\/\//i.test(url)) objectKey = url;
    var fileName = payload.fileName || payload.file_name || item.bodyText || 'download';
    var bucket = payload.bucket || 'im-attachments';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    if (objectKey) {
      try {
        var dl = storageDownloadEndpoint(objectKey, bucket, fileName);
        var resp = await fetch(dl, { headers: token ? { Authorization: 'Bearer ' + token } : {} });
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        var blob = await resp.blob();
        var blobUrl = URL.createObjectURL(blob);
        var a = document.createElement('a');
        a.href = blobUrl;
        a.download = fileName.replace(/^\[[^\]]+\]\s*/, '');
        document.body.appendChild(a);
        a.click();
        a.remove();
        setTimeout(function () { URL.revokeObjectURL(blobUrl); }, 2000);
        return;
      } catch (e) {
        try {
          var signed = await resolveMediaUrl(objectKey, bucket);
          if (signed) {
            var r2 = await fetch(signed);
            if (!r2.ok) throw new Error('HTTP ' + r2.status);
            var b2 = await r2.blob();
            var u2 = URL.createObjectURL(b2);
            var a2 = document.createElement('a');
            a2.href = u2;
            a2.download = fileName.replace(/^\[[^\]]+\]\s*/, '');
            document.body.appendChild(a2);
            a2.click();
            a2.remove();
            setTimeout(function () { URL.revokeObjectURL(u2); }, 2000);
            return;
          }
        } catch (e2) {}
      }
    }
    if (!url) throw new Error('无下载地址');
    if (/^https?:\/\//i.test(url)) {
      try {
        var r3 = await fetch(url, { mode: 'cors' });
        if (r3.ok) {
          var b3 = await r3.blob();
          var u3 = URL.createObjectURL(b3);
          var link = document.createElement('a');
          link.href = u3;
          link.download = fileName.replace(/^\[[^\]]+\]\s*/, '');
          document.body.appendChild(link);
          link.click();
          link.remove();
          setTimeout(function () { URL.revokeObjectURL(u3); }, 2000);
          return;
        }
      } catch (e3) {}
      window.open(url, '_blank', 'noopener');
      return;
    }
    throw new Error('无下载地址');
  }
  function mediaTimeLabel(iso) {
    if (!iso) return '';
    var d = new Date(iso);
    if (isNaN(d.getTime())) return String(iso).slice(0, 10);
    var now = new Date();
    var pad = function (n) { return n < 10 ? '0' + n : '' + n; };
    if (d.toDateString() === now.toDateString()) return '今 ' + pad(d.getHours()) + ':' + pad(d.getMinutes());
    return (d.getMonth() + 1) + '-' + pad(d.getDate());
  }
  function mediaIcon(kind, fileName) {
    if (kind === 'IMAGE') return 'ti-photo';
    var n = String(fileName || '').toLowerCase();
    if (n.indexOf('.xls') >= 0) return 'ti-file-type-xls';
    if (n.indexOf('.doc') >= 0) return 'ti-file-type-doc';
    if (n.indexOf('.pdf') >= 0) return 'ti-file-type-pdf';
    if (n.indexOf('.zip') >= 0 || n.indexOf('.rar') >= 0) return 'ti-file-type-zip';
    return 'ti-file';
  }
  var c13MediaCache = [];
  function renderMediaRow(item) {
    var payload = parsePayload(item.payload);
    var kind = item.kind || 'FILE';
    var title = (payload.fileName || item.bodyText || kind).replace(/^\[[^\]]+\]\s*/, '');
    var sender = (item.sender && item.sender.displayName) || item.senderDisplayName || '';
    var time = mediaTimeLabel(item.createdAt);
    var objectKey = String(payload.objectKey || payload.object_key || '').trim();
    var urlRaw = String(payload.url || payload.previewUrl || '').trim();
    if (!objectKey && urlRaw && !/^https?:\/\//i.test(urlRaw)) objectKey = urlRaw;
    var bucket = payload.bucket || 'im-attachments';
    var row = document.createElement('div');
    row.className = 'upload-slot filled dunes-c13-row';
    row.style.marginBottom = '7px';
    row.dataset.messageId = item.id || '';
    row.dataset.kind = kind;
    row.dataset.objectKey = objectKey;
    row.dataset.bucket = bucket;
    row.dataset.fileName = title;
    if (kind === 'IMAGE' && objectKey) {
      row.innerHTML = '<img class="c13-thumb" alt="" data-object-key="' + esc(objectKey) + '" data-bucket="' + esc(bucket) + '">'
        + '<span class="us-t">' + esc(title) + '</span>'
        + '<span style="font-family:var(--mono);font-size:9px;color:var(--text-3);margin-right:5px">' + esc(sender) + ' · ' + esc(time) + '</span>'
        + '<i class="ti ti-download us-x"></i>';
    } else {
      var ic = mediaIcon(kind, title);
      var icColor = kind === 'LINK' ? 'var(--accent)' : 'var(--text-2)';
      row.innerHTML = '<i class="ti ' + ic + ' us-ic" style="color:' + icColor + '"></i>'
        + '<span class="us-t">' + esc(title) + '</span>'
        + '<span style="font-family:var(--mono);font-size:9px;color:var(--text-3);margin-right:5px">' + esc(sender) + ' · ' + esc(time) + '</span>'
        + '<i class="ti ti-download us-x"></i>';
    }
    return row;
  }
  async function hydrateC13Thumbs(root) {
    if (!root) return;
    var imgs = root.querySelectorAll('img[data-object-key]');
    for (var i = 0; i < imgs.length; i++) {
      var img = imgs[i];
      if (img.dataset.hydrated === '1') continue;
      var key = img.getAttribute('data-object-key') || '';
      if (!key) continue;
      try {
        var url = await resolveMediaUrl(key, img.getAttribute('data-bucket') || 'im-attachments');
        if (url) { img.src = url; img.dataset.hydrated = '1'; img.dataset.fullUrl = url; }
      } catch (e) {}
    }
  }
  function wireC13Rows(root) {
    if (!root || root.dataset.wired) return;
    root.dataset.wired = '1';
    root.addEventListener('click', async function (e) {
      var row = e.target.closest('.dunes-c13-row');
      if (!row) return;
      e.preventDefault();
      var kind = row.dataset.kind || '';
      var item = c13MediaCache.find(function (m) { return String(m.id) === String(row.dataset.messageId); });
      if (!item) return;
      try {
        if (kind === 'IMAGE') {
          var thumb = row.querySelector('img.c13-thumb');
          var url = (thumb && (thumb.dataset.fullUrl || thumb.src)) || '';
          if (!url && thumb) url = await resolveMediaUrl(thumb.getAttribute('data-object-key'), thumb.getAttribute('data-bucket'));
          if (url && window.__dunesOpenImageViewer) window.__dunesOpenImageViewer(url);
          else if (url) window.open(url, '_blank');
          return;
        }
        if (kind === 'LINK') {
          var p = parsePayload(item.payload);
          var link = p.url || item.bodyText || '';
          if (link) window.open(link, '_blank');
          return;
        }
        await downloadMediaItem(item);
        toast('已开始下载');
      } catch (err) { toast((err && err.message) || '打开失败'); }
    });
  }
  function wireC13Actions() {
    var screen = document.querySelector('.screen[data-screen="C13"]');
    if (!screen) return;
    var backBtn = screen.querySelector('.action-bar .act-btn[data-go="C6"]');
    if (backBtn && !backBtn.dataset.navWired) {
      backBtn.dataset.navWired = '1';
      backBtn.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        if (typeof go === 'function') go('C6');
        else if (typeof setScreen === 'function') setScreen('C6', true);
      }, true);
    }
    var batchBtn = screen.querySelector('.action-bar .act-btn.primary');
    if (batchBtn && !batchBtn.dataset.wired) {
      batchBtn.dataset.wired = '1';
      batchBtn.addEventListener('click', async function (e) {
        e.preventDefault();
        var items = c13MediaCache.filter(function (m) {
          return m.kind === 'IMAGE' || m.kind === 'FILE';
        });
        if (!items.length) { toast('暂无可下载文件'); return; }
        var ok = await dlgConfirm('将依次下载 ' + items.length + ' 个文件，是否继续？');
        if (!ok) return;
        toast('开始批量下载…');
        for (var i = 0; i < items.length; i++) {
          try {
            await downloadMediaItem(items[i]);
            await new Promise(function (r) { setTimeout(r, 400); });
          } catch (err) { console.warn('batch download', items[i].id, err); }
        }
        toast('批量下载完成');
      });
    }
  }
  async function loadConvMedia() {
    var convId = currentConvId();
    var box = document.getElementById('c13-api-rows');
    if (!box) return;
    wireC13Actions();
    if (!convId) {
      box.innerHTML = '<div style="padding:16px;text-align:center;color:var(--text-3);font-size:12px">请先进入群聊</div>';
      return;
    }
    box.innerHTML = '<div style="padding:16px;text-align:center;color:var(--text-3);font-size:12px">加载中…</div>';
    try {
      var d = window.__dunesGroupDetail || {};
      var title = d.title || '群聊';
      var crumb = document.querySelector('.screen[data-screen="C13"] .ds-crumb');
      var nameEl = document.querySelector('.screen[data-screen="C13"] .ds-name');
      if (crumb) crumb.textContent = title + ' · 媒体';
      var j = await apiFetch('/conversations/' + convId + '/media?size=50');
      if (!j.success) throw new Error(j.message || '加载失败');
      var items = (j.data && j.data.items) || [];
      c13MediaCache = items;
      var total = j.data && j.data.total != null ? j.data.total : items.length;
      if (nameEl) nameEl.textContent = '图片 · 视频 · 文件 · ' + total + ' 项';
      box.innerHTML = '';
      if (!items.length) {
        box.innerHTML = '<div style="padding:24px;text-align:center;color:var(--text-3);font-size:12px">暂无图片、视频或文件</div>';
        return;
      }
      items.forEach(function (item) { box.appendChild(renderMediaRow(item)); });
      wireC13Rows(box);
      hydrateC13Thumbs(box);
    } catch (e) {
      box.innerHTML = '<div style="padding:16px;text-align:center;color:var(--coral);font-size:12px">' + esc((e && e.message) || '加载失败') + '</div>';
    }
  }
  function ensurePickerOverlay() {
    var el = document.getElementById('dunes-member-picker');
    if (el) return el;
    el = document.createElement('div');
    el.id = 'dunes-member-picker';
    el.style.cssText = 'display:none;position:fixed;inset:0;background:rgba(0,0,0,.35);z-index:120;align-items:flex-end;justify-content:center';
    el.innerHTML = '<div class="dunes-member-sheet" style="width:100%;max-width:430px;background:var(--bg-app);border-radius:16px 16px 0 0;max-height:72vh;display:flex;flex-direction:column">'
      + '<div style="padding:12px 16px;border-bottom:1px solid var(--border-soft);display:flex;align-items:center;justify-content:space-between">'
      + '<span id="dunes-member-picker-title" style="font-weight:700;font-size:14px">选择成员</span>'
      + '<button type="button" id="dunes-member-picker-close" style="border:none;background:transparent;font-size:18px;cursor:pointer">&times;</button></div>'
      + '<div style="padding:8px 12px 0"><div class="gsearch-bar" style="margin:0"><i class="ti ti-search"></i>'
      + '<input id="dunes-member-picker-search" placeholder="搜索姓名 / 部门" style="border:none;background:transparent;flex:1;font-size:13px"></div></div>'
      + '<div id="dunes-member-picker-list" style="overflow-y:auto;padding:8px 12px 16px;flex:1"></div>'
      + '<div style="padding:10px 12px 16px;border-top:1px solid var(--border-soft)">'
      + '<button type="button" id="dunes-member-picker-ok" style="width:100%;padding:12px;border:none;border-radius:10px;background:var(--accent);color:#fff;font-weight:700">确定</button></div></div>';
    document.body.appendChild(el);
    el.querySelector('#dunes-member-picker-close').addEventListener('click', closePicker);
    el.addEventListener('click', function (e) { if (e.target === el) closePicker(); });
    el.querySelector('#dunes-member-picker-ok').addEventListener('click', confirmPicker);
    var searchInp = el.querySelector('#dunes-member-picker-search');
    if (searchInp && !searchInp.dataset.wired) {
      searchInp.dataset.wired = '1';
      var st = null;
      searchInp.addEventListener('input', function () {
        if (st) clearTimeout(st);
        st = setTimeout(function () {
          if (pickState) renderPickerList(pickState.candidates, pickState.excludeIds, searchInp.value.trim());
        }, 200);
      });
    }
    return el;
  }
  function closePicker() {
    var el = document.getElementById('dunes-member-picker');
    if (el) el.style.display = 'none';
    pickState = null;
    window.__dunesMemberPickState = null;
  }
  function openMemberPicker(opts) {
    opts = opts || {};
    pickState = {
      mode: opts.mode || 'add',
      convId: opts.convId || currentConvId(),
      selected: new Set(),
      single: opts.mode === 'remove',
      candidates: opts.candidates || null,
      excludeIds: opts.excludeIds || []
    };
    window.__dunesMemberPickState = pickState;
    var overlay = ensurePickerOverlay();
    overlay.style.display = 'flex';
    document.getElementById('dunes-member-picker-title').textContent =
      pickState.mode === 'remove' ? '选择要移除的成员' : '从通讯录选择成员';
    var searchInp = document.getElementById('dunes-member-picker-search');
    if (searchInp) searchInp.value = '';
    renderPickerList(pickState.candidates, pickState.excludeIds, '');
  }
  function renderPickerFlatRows(list, rows) {
    list.innerHTML = rows.map(function (c) {
      var uid = Number(c.userId);
      var on = pickState && pickState.selected.has(uid) ? ' on' : '';
      var nm = (c.displayName || '') + (c.enabled === false ? '-停用' : '');
      var meta = '';
      if (c.title) meta += '<span>' + esc(c.title) + '</span>';
      var dept = c.department || c.departmentName || '';
      if (dept) meta += '<span>' + esc(dept) + '</span>';
      return '<div class="contact-pick-row tappable' + on + '" data-pick-user-id="' + uid + '">'
        + '<div class="cp-check"><i class="ti ti-check"></i></div>'
        + '<div class="cp-av no-initial ' + personCls(uid) + '" data-avatar-user-id="' + uid + '"> </div>'
        + '<div class="cp-bd"><div class="cp-nm">' + esc(nm) + '</div>'
        + '<div class="cp-m">' + meta + '</div></div></div>';
    }).join('');
    if (pickApi.wirePickRows) pickApi.wirePickRows(list, true);
    hydrateAvatarsIn(list);
  }
  async function renderPickerList(candidates, excludeIds, query) {
    var list = document.getElementById('dunes-member-picker-list');
    if (!list) return;
    var pickApi = window.__dunesContactsPick || window.DunesContacts || {};
    list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-3)">加载中…</div>';
    var exclude = {};
    (excludeIds || []).forEach(function (id) { exclude[String(id)] = true; });
    if (candidates) {
      var flat = (candidates || []).filter(function (c) {
        var uid = Number(c.userId);
        return uid && uid !== devUserId() && !exclude[String(uid)] && !isContactDisabled(c);
      });
      if (!flat.length) {
        list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-3)">暂无可选成员</div>';
        return;
      }
      list.classList.remove('dept-tree');
      renderPickerFlatRows(list, flat);
      return;
    }
    list.classList.add('dept-tree');
    try {
      var qs = query ? ('&q=' + encodeURIComponent(query)) : '';
      var j = await apiFetch('/contacts?view=org' + qs);
      if (!j.success) throw new Error(j.message || 'contacts failed');
      var d = j.data || {};
      var depts = d.departments || [];
      var items = d.items || [];
      list.innerHTML = '';
      if (query) {
        items = items.filter(function (c) {
          var uid = Number(c.userId);
          return uid && uid !== devUserId() && !exclude[String(uid)] && !isContactDisabled(c);
        });
        if (!items.length) {
          list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-3)">无匹配联系人</div>';
          return;
        }
        list.classList.remove('dept-tree');
        renderPickerFlatRows(list, items);
        return;
      }
      if (!depts.length) {
        list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-3)">暂无组织数据</div>';
        return;
      }
      depts.forEach(function (dep) {
        rememberDeptProfiles(dep);
        var allowDeptSelect = !pickState || !pickState.single;
        if (pickApi.renderDeptBlock) {
          list.insertAdjacentHTML('beforeend', pickApi.renderDeptBlock(dep, true, allowDeptSelect));
        }
      });
      if (pickApi.wireDeptToggle) pickApi.wireDeptToggle(list);
      if (pickApi.wireDeptSelectAll) pickApi.wireDeptSelectAll(list, true);
      if (pickApi.wirePickRows) pickApi.wirePickRows(list, true);
      hydrateAvatarsIn(list);
      if (pickApi.refreshOnlineDots) pickApi.refreshOnlineDots();
    } catch (e) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-3)">加载失败：' + esc(e.message || e) + '</div>';
      console.warn('DunesContacts.renderPickerList', e);
    }
  }
  async function confirmPicker() {
    if (!pickState || !pickState.convId) return;
    var ids = Array.from(pickState.selected);
    if (!ids.length) { toast('请选择成员'); return; }
    try {
      if (pickState.mode === 'remove') {
        var j = await apiFetch('/conversations/' + pickState.convId + '/members/' + ids[0], { method: 'DELETE' });
        if (!j.success) throw new Error(j.message || '移除失败');
        toast('已移除成员');
      } else {
        var aj = await apiFetch('/conversations/' + pickState.convId + '/members', {
          method: 'POST',
          body: JSON.stringify({ userIds: ids })
        });
        if (!aj.success) throw new Error(aj.message || '添加失败');
        toast('已添加 ' + (aj.data && aj.data.added != null ? aj.data.added : ids.length) + ' 人');
      }
      closePicker();
      await loadConvInfo();
      if (window.DunesImChat && typeof window.DunesImChat.reloadActiveChat === 'function') {
        window.DunesImChat.reloadActiveChat('C2');
      }
    } catch (e) {
      toast((e && e.message) || '操作失败');
    }
  }
  function sortGroupMembers(members) {
    return (members || []).slice().sort(function (a, b) {
      var aOwner = String(a.role || '').toUpperCase() === 'OWNER';
      var bOwner = String(b.role || '').toUpperCase() === 'OWNER';
      if (aOwner && !bOwner) return -1;
      if (!aOwner && bOwner) return 1;
      var an = String(a.displayName || '');
      var bn = String(b.displayName || '');
      try { return an.localeCompare(bn, 'zh-CN'); } catch (e) { return an.localeCompare(bn); }
    });
  }
  function hideC6FlowPushRow() {
    document.querySelectorAll('.screen[data-screen="C6"] .gi-row').forEach(function (row) {
      var title = row.querySelector('.gr-t');
      if (title && title.textContent.trim() === '流转消息推送') {
        row.classList.add('c6-flow-push-hidden');
        row.style.display = 'none';
      }
    });
  }
  function wireSettings(detail) {
    hideC6FlowPushRow();
    var rows = document.querySelectorAll('.screen[data-screen="C6"] .gi-row');
    rows.forEach(function (row, idx) {
      var title = row.querySelector('.gr-t');
      if (!title) return;
      var t = title.textContent.trim();
      if (t === '消息免打扰' || t === '置顶聊天') {
        if (row.dataset.settingsWired) return;
        row.dataset.settingsWired = '1';
        row.classList.add('tappable');
        var toggle = row.querySelector('.toggle');
        row.addEventListener('click', async function (e) {
          e.preventDefault();
          e.stopPropagation();
          var convId = currentConvId();
          if (!convId) return;
          var muted = t === '消息免打扰';
          var body = muted ? { muted: !(toggle && toggle.classList.contains('on')) } : { pinned: !(toggle && toggle.classList.contains('on')) };
          try {
            var j = await apiFetch('/conversations/' + convId + '/my-settings', { method: 'PATCH', body: JSON.stringify(body) });
            if (j.success && toggle) {
              if (muted ? j.data.muted : j.data.pinned) toggle.classList.add('on');
              else toggle.classList.remove('on');
            }
            if (window.DunesInbox && window.DunesInbox.loadC1) window.DunesInbox.loadC1();
          } catch (err) { toast('设置失败'); }
        });
      }
    });
    if (detail) {
      rows.forEach(function (row) {
        var title = row.querySelector('.gr-t');
        if (!title) return;
        if (title.textContent.trim() === '消息免打扰') {
          var tg = row.querySelector('.toggle');
          if (tg) { if (detail.muted) tg.classList.add('on'); else tg.classList.remove('on'); }
        }
        if (title.textContent.trim() === '置顶聊天') {
          var tg2 = row.querySelector('.toggle');
          if (tg2) { if (detail.pinned) tg2.classList.add('on'); else tg2.classList.remove('on'); }
        }
      });
    }
  }
  function wireDanger(detail) {
    var clearBtn = document.getElementById('c6-clear-history');
    if (clearBtn) {
      clearBtn.style.display = 'none';
    }
    var dissolveBtn = document.getElementById('c6-dissolve-group');
    if (dissolveBtn) {
      var dissolved = !!(detail && (detail.dissolved || detail.isDissolved || detail.status === 'DISSOLVED' || detail.frozen));
      var showDissolve = !!(detail && detail.isOwner && !dissolved);
      dissolveBtn.style.display = showDissolve ? 'block' : 'none';
      if (!dissolveBtn.dataset.wired) {
        dissolveBtn.dataset.wired = '1';
        dissolveBtn.addEventListener('click', async function (e) {
          e.preventDefault();
          var d = window.__dunesGroupDetail || detail;
          if (!d || !d.isOwner) { toast('仅群主可解散群聊'); return; }
          var convId = currentConvId();
          if (!convId) return;
          if (!(await dlgConfirm('解散后群聊仍保留历史记录，但所有成员将无法再发送消息或操作群设置。确定解散？'))) return;
          try {
            var j = await apiFetch('/conversations/' + convId + '/dissolve', { method: 'POST' });
            if (!j.success) throw new Error(j.message || '解散失败');
            toast('群聊已解散');
            d.dissolved = true;
            d.isDissolved = true;
            d.status = 'DISSOLVED';
            window.__dunesGroupDetail = d;
            dissolveBtn.style.display = 'none';
            if (window.DunesImChat && typeof window.DunesImChat.reloadActiveChat === 'function') {
              window.DunesImChat.reloadActiveChat('C2');
            }
            await loadConvInfo();
          } catch (err) { toast((err && err.message) || '解散失败'); }
        });
      }
    }
    var leaveBtn = document.getElementById('c6-leave-group');
    if (leaveBtn) {
      var dissolved = !!(detail && (detail.dissolved || detail.isDissolved || detail.status === 'DISSOLVED' || detail.frozen));
      var canLeave = !!(detail && (detail.canLeave || dissolved));
      leaveBtn.style.display = canLeave ? 'block' : 'none';
      leaveBtn.style.opacity = canLeave ? '1' : '.5';
      leaveBtn.style.cursor = canLeave ? 'pointer' : 'not-allowed';
      if (!leaveBtn.dataset.wired) {
        leaveBtn.dataset.wired = '1';
        leaveBtn.addEventListener('click', async function (e) {
          e.preventDefault();
          var d = window.__dunesGroupDetail || detail;
          var dissolvedLeave = !!(d && (d.dissolved || d.isDissolved || d.status === 'DISSOLVED' || d.frozen));
          if (!d || (!d.canLeave && !dissolvedLeave)) {
            toast('系统群不可退出');
            return;
          }
          var convId = currentConvId();
          if (!convId) return;
          if (!(await dlgConfirm(dissolvedLeave ? '该群已解散，退出后将从你的会话列表中移除。确定退出？' : '确定退出该群聊？'))) return;
          try {
            var exitFn = window.DunesInbox && window.DunesInbox.exitGroupMembership;
            if (typeof exitFn !== 'function') throw new Error('退出功能未就绪，请返回会话列表后重试');
            var serverRemoved = await exitFn(convId, dissolvedLeave);
            var permanent = dissolvedLeave || !serverRemoved;
            var okMsg = dissolvedLeave ? '该群已解散，已为你退出' : '已退出群聊';
            if (window.DunesInbox && window.DunesInbox.finishExitGroup) {
              window.DunesInbox.finishExitGroup(convId, okMsg, permanent);
            } else { toast(okMsg); if (typeof go === 'function') go('C1'); }
          } catch (err) {
            toast(String((err && err.message) || '退出失败'));
          }
        });
      }
    }
  }
  function wireMembers(detail) {
    var add = document.getElementById('c6-add-member');
    if (add && !add.dataset.wired) {
      add.dataset.wired = '1';
      add.addEventListener('click', function (e) {
        e.preventDefault();
        var d = window.__dunesGroupDetail || detail;
        if (!d || !d.isOwner) { toast('仅群主可添加成员'); return; }
        var exclude = (d.members || []).map(function (m) { return Number(m.userId); });
        openMemberPicker({ mode: 'add', convId: currentConvId(), excludeIds: exclude });
      });
    }
    var rem = document.getElementById('c6-remove-member');
    if (rem && !rem.dataset.wired) {
      rem.dataset.wired = '1';
      rem.addEventListener('click', function (e) {
        e.preventDefault();
        var d = window.__dunesGroupDetail || detail;
        if (!d || !d.isOwner) { toast('仅群主可移除成员'); return; }
        var candidates = (d.members || []).filter(function (m) {
          return Number(m.userId) !== devUserId();
        }).map(function (m) {
          return { userId: m.userId, displayName: m.displayName, department: '', title: m.role || '' };
        });
        openMemberPicker({ mode: 'remove', convId: currentConvId(), candidates: candidates, single: true });
      });
    }
  }
  async function loadLinkedApprovals(d) {
    var section = document.getElementById('c6-linked-section');
    var box = document.getElementById('c6-linked-rows');
    if (!box) return;
    box.innerHTML = '';
    var bt = d.businessType;
    var bid = d.businessId;
    if (!bt || !bid) {
      if (section) section.style.display = 'none';
      box.style.display = 'none';
      return;
    }
    if (section) section.style.display = '';
    box.style.display = '';
    try {
      var j = await apiFetch('/approvals/' + encodeURIComponent(bt) + '/' + bid);
      if (!j.success || !j.data) {
        box.innerHTML = '<div class="gi-row"><div class="gr-bd"><div class="gr-d" style="padding:12px 16px;color:var(--text-3)">暂无关联审批数据</div></div></div>';
        return;
      }
      var trail = j.data;
      var steps = trail.steps || trail.items || [];
      var title = trail.title || trail.name || (bt + ' #' + bid);
      var status = trail.status || trail.currentNode || '';
      var html = '<div class="gi-row tappable" data-go="B14">'
        + '<div class="gr-ic accent"><i class="ti ti-clipboard-text"></i></div>'
        + '<div class="gr-bd"><div class="gr-t">' + esc(bt) + ' #' + bid + ' · ' + esc(String(title)) + '</div>'
        + '<div class="gr-d">' + esc(String(trail.routeType || trail.kind || bt)) + (status ? (' · ' + esc(String(status))) : '') + '</div></div>'
        + '<div class="gr-r"><i class="ti ti-chevron-right chev"></i></div></div>';
      if (steps.length) {
        html += '<div class="gi-row"><div class="gr-ic"><i class="ti ti-route"></i></div><div class="gr-bd">'
          + '<div class="gr-t">审批节点 · ' + steps.length + ' 步</div>'
          + '<div class="gr-d">' + esc(String(steps[steps.length - 1].node || steps[steps.length - 1].name || '')) + '</div></div></div>';
      }
      box.innerHTML = html;
    } catch (e) {
      box.innerHTML = '<div class="gi-row"><div class="gr-bd"><div class="gr-d" style="padding:12px 16px;color:var(--text-3)">暂无关联审批数据</div></div></div>';
    }
  }
  function wireRename(detail) {
    var row = document.getElementById('c6-rename-row');
    var val = document.getElementById('c6-title-value');
    if (val && detail && detail.title) {
      val.innerHTML = esc(detail.title) + '<i class="ti ti-chevron-right chev"></i>';
    }
    if (!row || row.dataset.wired) return;
    row.dataset.wired = '1';
    row.addEventListener('click', async function (e) {
      e.preventDefault();
      e.stopPropagation();
      var d = window.__dunesGroupDetail || detail;
      if (!d || !d.isOwner) { toast('仅群主可修改群名称'); return; }
      var next = await dlgPrompt('修改群名称', d.title || '');
      if (next == null) return;
      next = String(next).trim();
      if (!next) { toast('群名称不能为空'); return; }
      try {
        var j = await apiFetch('/conversations/' + currentConvId(), {
          method: 'PATCH',
          body: JSON.stringify({ title: next })
        });
        if (!j.success) throw new Error(j.message || '修改失败');
        toast('群名称已更新');
        await loadConvInfo();
        if (window.DunesImChat && window.DunesImChat.reloadActiveChat) window.DunesImChat.reloadActiveChat('C2');
        if (window.DunesInbox && window.DunesInbox.loadC1) window.DunesInbox.loadC1();
      } catch (err) { toast((err && err.message) || '修改失败'); }
    });
  }
  function wireC6Nav() {
    var searchRow = document.getElementById('c6-search-row');
    if (searchRow && !searchRow.dataset.navWired) {
      searchRow.dataset.navWired = '1';
      searchRow.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        window.__dunesHistoryReturnScreen = 'C6';
        if (typeof go === 'function') go('C12');
        else if (typeof setScreen === 'function') setScreen('C12', false);
      }, true);
    }
    var mediaRow = document.querySelector('.screen[data-screen="C6"] .gi-row[data-go="C13"]');
    if (mediaRow && !mediaRow.dataset.navWired) {
      mediaRow.dataset.navWired = '1';
      mediaRow.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        window.__dunesHistoryReturnScreen = 'C6';
        if (typeof go === 'function') go('C13');
        else if (typeof setScreen === 'function') setScreen('C13', false);
      }, true);
    }
  }
  function syncC6Header(d) {
    var hdrNm = document.querySelector('.screen[data-screen="C6"] .cv-nm');
    var hdrSub = document.querySelector('.screen[data-screen="C6"] .cv-sub');
    var members = d.members || [];
    if (hdrNm) hdrNm.textContent = '群信息';
    if (hdrSub) {
      var kindLabel = d.kind === 'WORKGROUP_APPROVAL' ? '审批工作群' : (d.kind === 'WORKGROUP' ? '工作群' : '群聊');
      hdrSub.textContent = kindLabel + ' · ' + members.length + ' 成员';
    }
  }
  async function loadMediaCount(convId) {
    var el = document.getElementById('c6-media-count');
    if (!el || !convId) return;
    try {
      var j = await apiFetch('/conversations/' + convId + '/media?size=1');
      var n = j.success && j.data && j.data.total != null ? j.data.total : (j.data && j.data.items ? j.data.items.length : 0);
      el.textContent = String(n || 0);
    } catch (e) { el.textContent = '0'; }
  }
  async function loadConvInfo() {
    var convId = currentConvId();
    if (!convId) return;
    if (window.DunesScreenLoader) window.DunesScreenLoader.show('C6', '加载群信息…');
    try {
      var j = await apiFetch('/conversations/' + convId + '/info');
      if (!j.success || !j.data) return;
      var d = j.data;
      window.__dunesGroupDetail = d;
      window.__dunesGroupMembers = (d.members || []).filter(function (m) {
        return Number(m.userId) !== devUserId();
      });
      var nm = document.getElementById('c6-gi-nm');
      var sub = document.getElementById('c6-gi-sub');
      var lbl = document.getElementById('c6-member-label');
      if (nm) nm.textContent = d.title || '群聊';
      syncC6Header(d);
      var dissolved = !!(d.dissolved || d.isDissolved || d.status === 'DISSOLVED' || d.frozen);
      if (sub) {
        var bits = [];
        if (dissolved) bits.push('已解散');
        if (d.kind === 'WORKGROUP_APPROVAL') bits.push('审批工作群');
        else if (d.kind === 'WORKGROUP') bits.push('工作群');
        else bits.push(d.kind || '群聊');
        if (d.createdAt) bits.push('创建于 ' + String(d.createdAt).slice(0, 10));
        sub.textContent = bits.join(' · ');
      }
      var members = sortGroupMembers(d.members || []);
      if (lbl) lbl.textContent = '群成员 · ' + members.length + ' 人';
      var grid = document.getElementById('c6-member-grid');
      if (grid) {
        grid.innerHTML = '';
        members.forEach(function (m) {
          var div = document.createElement('div');
          div.className = 'gi-member tappable';
          div.dataset.contactUserId = m.userId;
          div.dataset.go = 'C9';
          var initial = (m.displayName || '用户').slice(0, 1);
          var me = Number(m.userId) === devUserId() ? ' ·我' : '';
          div.innerHTML = '<div class="gm-av ' + personCls(m.userId) + '">' + esc(initial) + '</div>'
            + '<div class="gm-nm">' + esc(m.displayName || '') + (me ? '<span style="color:var(--accent);font-size:7px;font-weight:700">' + me + '</span>' : '') + '</div>';
          grid.appendChild(div);
        });
        if (d.isOwner && !dissolved) {
          var add = document.createElement('div');
          add.className = 'gi-member tappable';
          add.id = 'c6-add-member';
          add.innerHTML = '<div class="gm-av add"><i class="ti ti-plus"></i></div><div class="gm-nm">添加</div>';
          grid.appendChild(add);
          var rem = document.createElement('div');
          rem.className = 'gi-member tappable';
          rem.id = 'c6-remove-member';
          rem.innerHTML = '<div class="gm-av remove"><i class="ti ti-minus"></i></div><div class="gm-nm">移除</div>';
          grid.appendChild(rem);
        }
        wireMembers(d);
      }
      wireSettings(d);
      wireDanger(d);
      wireRename(d);
      wireC6Nav();
      loadLinkedApprovals(d);
      loadMediaCount(convId);
    } catch (e) { console.warn('DunesGroupInfo.loadConvInfo', e); }
    finally {
      if (window.DunesScreenLoader) window.DunesScreenLoader.hide('C6');
    }
  }
  function onScreen(id) {
    if (id === 'C6') loadConvInfo();
    if (id === 'C13') loadConvMedia();
  }
  return { loadConvInfo: loadConvInfo, loadConvMedia: loadConvMedia, onScreen: onScreen, openMemberPicker: openMemberPicker };
})();
''';

  static const bootstrapJs = r'''
(function () {
  if (window.__dunesFlutterReady) return;
  window.__dunesFlutterReady = true;

  document.body.classList.add('flutter-app-mode');
  window.DunesScreenLoader = (function () {
    function phone(screen) {
      if (!screen) return null;
      return screen.querySelector('.phone-screen') || screen;
    }
    function ensureMask(screen, msg) {
      var host = phone(screen);
      if (!host) return null;
      var mask = host.querySelector('.dunes-screen-loading-mask');
      if (!mask) {
        mask = document.createElement('div');
        mask.className = 'dunes-screen-loading-mask';
        mask.innerHTML = '<div class="dunes-screen-loading-inner"><div class="dunes-screen-loading-spin"></div><span class="dunes-screen-loading-text">加载中…</span></div>';
        host.appendChild(mask);
      }
      var t = mask.querySelector('.dunes-screen-loading-text');
      if (t && msg) t.textContent = msg;
      return mask;
    }
    return {
      show: function (screenId, msg) {
        var screen = document.querySelector('.screen[data-screen="' + screenId + '"]');
        if (!screen) return;
        var mask = ensureMask(screen, msg || '加载中…');
        if (mask) mask.style.display = 'flex';
        screen.classList.add('dunes-screen-loading');
      },
      hide: function (screenId) {
        var screen = document.querySelector('.screen[data-screen="' + screenId + '"]');
        if (!screen) return;
        screen.classList.remove('dunes-screen-loading');
        var host = phone(screen);
        var mask = host && host.querySelector('.dunes-screen-loading-mask');
        if (mask) mask.style.display = 'none';
      }
    };
  })();
  (function ensureNovaOwnerStorage() {
    var uid = parseInt(localStorage.getItem('dunes_user_id') || '0', 10) || 0;
    var owner = parseInt(localStorage.getItem('dunes_nova_owner_uid') || '0', 10) || 0;
    if (uid > 0 && owner > 0 && owner !== uid) {
      if (window.DunesNovaApi && typeof window.DunesNovaApi.clearAllAiLocalHistory === 'function') {
        window.DunesNovaApi.clearAllAiLocalHistory();
      } else {
        ['dunes_nova_conv_id', 'dunes_nova_local_history', 'dunes_nova_msgs_', 'dunes_nova_profile_session'].forEach(function (k) {
          try {
            if (k.indexOf('_') === k.length - 1) {
              var drop = [];
              for (var i = 0; i < localStorage.length; i++) {
                var key = localStorage.key(i);
                if (key && key.indexOf(k) === 0) drop.push(key);
              }
              drop.forEach(function (dk) { localStorage.removeItem(dk); });
            } else {
              localStorage.removeItem(k);
            }
          } catch (e) {}
        });
      }
    }
    if (uid > 0) {
      try { localStorage.setItem('dunes_nova_owner_uid', String(uid)); } catch (e2) {}
    }
  })();
  (function hidePrototypeMocks() {
    var c1 = document.getElementById('c1-conv-list');
    if (c1) { c1.innerHTML = ''; c1.classList.remove('dunes-api-ready'); }
    var z2 = document.getElementById('z2-noti-list');
    if (z2) z2.classList.remove('z2-api-ready');
    ['C5', 'C2'].forEach(function (sid) {
      var stream = document.querySelector('.screen[data-screen="' + sid + '"] .msg-stream');
      if (!stream) return;
      var boxId = sid === 'C2' ? 'c2-api-rows' : 'c5-api-rows';
      if (!document.getElementById(boxId)) {
        var box = document.createElement('div');
        box.id = boxId;
        stream.insertBefore(box, stream.firstChild);
      }
    });
  })();
  window.__dunesSelfUserId = parseInt(localStorage.getItem('dunes_user_id') || '0', 10) || 0;
  try {
    var _t = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    if (_t) {
      var _p = JSON.parse(atob(_t.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
      if (_p.userId != null) {
        var _n = Number(_p.userId);
        if (!isNaN(_n) && _n > 0) window.__dunesSelfUserId = _n;
      }
    }
  } catch (e) {}

  window.dunesNovaIconHtml = function (extraClass) {
    var src = window.__dunesNovaIconSrc || '';
    if (!src) return '<i class="ti ti-sparkles"></i>';
    var cls = 'nova-icon-img' + (extraClass ? ' ' + extraClass : '');
    return '<img class="' + cls + '" src="' + src + '" alt="云枢" draggable="false">';
  };
  window.dunesNovaAvatarHtml = function (avClass) {
    return '<div class="' + (avClass || 'msg-av-sm ai-bot') + '">' + window.dunesNovaIconHtml() + '</div>';
  };
  window.patchNovaIcons = function () {
    if (!window.dunesNovaIconHtml) return;
    if (window.__dunesNovaIconSrc) {
      document.querySelectorAll('[data-nova-icon]').forEach(function (el) {
        el.src = window.__dunesNovaIconSrc;
      });
    }
    document.querySelectorAll('.qj-cell[data-go="C4"] .qj-ic').forEach(function (el) {
      el.innerHTML = window.dunesNovaIconHtml();
    });
    document.querySelectorAll('.chat-section').forEach(function (el) {
      if (el.textContent.indexOf('云枢') < 0 && el.textContent.indexOf('NOVA') < 0) return;
      var ic = el.querySelector('i.ti-sparkles');
      if (!ic) return;
      var wrap = document.createElement('span');
      wrap.className = 'chat-section-nova-ic';
      wrap.innerHTML = window.dunesNovaIconHtml('nova-ic-sm');
      ic.replaceWith(wrap);
    });
    document.querySelectorAll('.chat-row .cr-av.ai-bot:not(.kb-chat), .msg-row .msg-av-sm.ai-bot:not(.kb-ai-av), .ai-hero .ah-av, .noti-card .nc-ic.nova-hist-ic').forEach(function (el) {
      if (el.querySelector('.nova-icon-img')) return;
      el.innerHTML = window.dunesNovaIconHtml();
    });
  };

  var style = document.createElement('style');
  style.textContent = __DUNES_CSS__;
  document.head.appendChild(style);

  (function installComingSoonMasks() {
    function soonLabel(blockName) {
      if (!blockName) return '<span class="soon-label"><span class="soon-main">敬请期待</span></span>';
      return (
        '<span class="soon-label">' +
        '<span class="soon-block">' + blockName + '</span>' +
        '<span class="soon-main">敬请期待</span></span>'
      );
    }

    function appendMask(wrap, blockName) {
      if (!wrap || wrap.querySelector(':scope > .coming-soon-mask')) return;
      var mask = document.createElement('div');
      mask.className = 'coming-soon-mask';
      mask.setAttribute('aria-hidden', 'true');
      mask.innerHTML = soonLabel(blockName || '');
      wrap.appendChild(mask);
      mask.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
      }, true);
    }

    function wrapElement(el, extraClass, blockName) {
      if (!el || el.closest('.coming-soon-wrap')) return;
      var outer = document.createElement('div');
      outer.className = 'coming-soon-wrap' + (extraClass ? ' ' + extraClass : '');
      el.parentNode.insertBefore(outer, el);
      outer.appendChild(el);
      appendMask(outer, blockName);
    }

    function wrapSiblingNodes(nodes, extraClass, blockName) {
      if (!nodes || !nodes.length) return;
      var wrap = document.createElement('div');
      wrap.className = 'coming-soon-wrap' + (extraClass ? ' ' + extraClass : '');
      var parent = nodes[0].parentNode;
      parent.insertBefore(wrap, nodes[0]);
      nodes.forEach(function (n) { wrap.appendChild(n); });
      appendMask(wrap, blockName);
    }

    function labelSection(b2Content, keyword, untilSelector) {
      var labels = b2Content.querySelectorAll('.section-label');
      for (var i = 0; i < labels.length; i++) {
        var label = labels[i];
        if ((label.textContent || '').indexOf(keyword) < 0) continue;
        if (label.closest('.coming-soon-wrap')) continue;
        var nodes = [label];
        var sibling = label.nextElementSibling;
        while (sibling) {
          if (untilSelector && sibling.matches(untilSelector)) break;
          nodes.push(sibling);
          sibling = sibling.nextElementSibling;
        }
        wrapSiblingNodes(nodes, 'dunes-soon-block', keyword);
        return;
      }
    }

    function labelSectionWithNextClass(b2Content, keyword, nextClass) {
      var labels = b2Content.querySelectorAll('.section-label');
      for (var i = 0; i < labels.length; i++) {
        var label = labels[i];
        if ((label.textContent || '').indexOf(keyword) < 0) continue;
        if (label.closest('.coming-soon-wrap')) continue;
        var nodes = [label];
        var next = label.nextElementSibling;
        if (next && next.classList.contains(nextClass)) nodes.push(next);
        wrapSiblingNodes(nodes, 'dunes-soon-block', keyword);
        return;
      }
    }

    var qjContent = document.querySelector('.screen[data-screen="QJ"] .content');
    if (qjContent && !qjContent.classList.contains('coming-soon-wrap')) {
      qjContent.classList.add('coming-soon-wrap');
      appendMask(qjContent, '千机');
    }

    var b2Content = document.querySelector('.screen[data-screen="B2"] .content');
    if (b2Content) {
      labelSection(b2Content, '薪资组成', '.work-profile, #wp-root');
      var wp = b2Content.querySelector('.work-profile, #wp-root');
      wrapElement(wp, 'dunes-soon-block', '工作画像');
      labelSectionWithNextClass(b2Content, '绩效考核', 'perf-card');
      labelSectionWithNextClass(b2Content, '福利', 'me-stats');
    }
  })();

  (function wireB2ComingSoonItems() {
    function showB2SoonToast() {
      var phone = document.querySelector('.screen[data-screen="B2"] .phone-screen');
      if (!phone) return;
      var t = phone.querySelector('.dunes-b2-soon-toast');
      if (!t) {
        t = document.createElement('div');
        t.className = 'dunes-b2-soon-toast';
        t.style.cssText = 'position:absolute;left:50%;bottom:88px;transform:translateX(-50%);max-width:88%;background:rgba(20,20,20,.88);color:#fff;padding:10px 14px;border-radius:9px;font-size:11.5px;z-index:80;text-align:center';
        phone.appendChild(t);
      }
      t.textContent = '敬请期待';
      t.style.display = 'block';
      clearTimeout(t._hideTimer);
      t._hideTimer = setTimeout(function () { t.style.display = 'none'; }, 2800);
    }
    function resetB2SoonVisuals(screen) {
      if (!screen) return;
      screen.querySelectorAll('.quick-stats .qs-cell[data-b2-soon]').forEach(function (cell) {
        var l = (cell.querySelector('.l') || {}).textContent || '';
        var v = cell.querySelector('.v');
        if (!v) return;
        if (l.indexOf('欠票') >= 0) v.innerHTML = '0<small>笔</small>';
        else v.textContent = '0';
      });
      screen.querySelectorAll('.menu-item[data-b2-soon]').forEach(function (mi) {
        var title = (mi.querySelector('.mi-t') || {}).textContent || '';
        var desc = mi.querySelector('.mi-d');
        var badge = mi.querySelector('.num-badge');
        if (title.indexOf('写汇报') >= 0) {
          if (desc) desc.textContent = '0 篇 · 0 草稿 · 日 / 周 / 月 / 季';
          if (badge) { badge.textContent = '0'; badge.className = 'num-badge gray'; }
        } else if (title.indexOf('会议纪要') >= 0) {
          if (desc) desc.textContent = '0 条 · 0 已生成 · 0 转写中';
          if (badge) { badge.textContent = '0'; badge.className = 'num-badge gray'; }
        } else if (title.indexOf('应付账单') >= 0) {
          if (desc) desc.textContent = '0 待处理 · 总 ¥0 · 灯塔联动';
          if (badge) { badge.textContent = '0'; badge.className = 'num-badge gray'; }
        } else if (title.indexOf('我的合同') >= 0) {
          if (desc) desc.textContent = '0 份 · 0 临期 · 寄出待回收 0';
        } else if (title.indexOf('欠票催办') >= 0) {
          if (desc) desc.textContent = '0 笔 · ¥0 · 欠 0 天';
          if (badge) { badge.textContent = '0'; badge.className = 'num-badge gray'; }
        }
      });
    }
    function lockB2Item(el) {
      if (!el || el.dataset.b2SoonLocked) return;
      el.dataset.b2SoonLocked = '1';
      el.dataset.b2Soon = '1';
      el.removeAttribute('data-go');
      el.classList.remove('tappable');
      el.classList.add('b2-soon-disabled');
      el.addEventListener('click', function (e) {
        e.preventDefault();
        e.stopPropagation();
        showB2SoonToast();
      }, true);
    }
    function installB2ComingSoon() {
      var screen = document.querySelector('.screen[data-screen="B2"]');
      if (!screen) return;
      screen.querySelectorAll('.quick-stats .qs-cell').forEach(function (cell) {
        var l = (cell.querySelector('.l') || {}).textContent || '';
        if (l.indexOf('本月经办') >= 0 || l.indexOf('欠票') >= 0) lockB2Item(cell);
      });
      screen.querySelectorAll('.menu-item').forEach(function (mi) {
        var title = (mi.querySelector('.mi-t') || {}).textContent || '';
        var go = mi.getAttribute('data-go') || '';
        var soon = go === 'W2' || go === 'MM0' || go === 'B4' || go === 'A7'
          || (go === 'B9' && title.indexOf('欠票') >= 0)
          || (go === 'B1' && title.indexOf('业务工作台') >= 0);
        if (soon) lockB2Item(mi);
      });
      resetB2SoonVisuals(screen);
    }
    window.__dunesInstallB2ComingSoon = installB2ComingSoon;
    window.__dunesResetB2SoonVisuals = function () {
      resetB2SoonVisuals(document.querySelector('.screen[data-screen="B2"]'));
    };
    installB2ComingSoon();
    (function wireC9BackButton() {
      var back = document.querySelector('.screen[data-screen="C9"] .ph-back');
      if (!back) return;
      back.removeAttribute('data-go');
      back.setAttribute('data-back', '1');
      back.classList.add('tappable');
    })();
    if (typeof fillQuickStats === 'function') {
      var origFillQuickStats = fillQuickStats;
      fillQuickStats = function (screenId, stats) {
        if (!stats) return origFillQuickStats(screenId, stats);
        var patched = Object.assign({}, stats);
        if (screenId === 'B2') {
          patched.outstandingInvoices = 0;
        }
        origFillQuickStats(screenId, patched);
        if (screenId === 'B2') resetB2SoonVisuals(document.querySelector('.screen[data-screen="B2"]'));
      };
    }
    if (typeof applyMyStats === 'function') {
      var origApplyMyStats = applyMyStats;
      applyMyStats = function (stats) {
        if (!stats) return origApplyMyStats(stats);
        var patched = Object.assign({}, stats);
        patched.outstandingInvoices = 0;
        origApplyMyStats(patched);
        resetB2SoonVisuals(document.querySelector('.screen[data-screen="B2"]'));
      };
    }
    setTimeout(function () {
      if (window.WorkbenchLive && typeof window.WorkbenchLive.refreshB2Menu === 'function') {
        var origRefreshB2Menu = window.WorkbenchLive.refreshB2Menu;
        window.WorkbenchLive.refreshB2Menu = function (stats) {
          origRefreshB2Menu(stats);
          resetB2SoonVisuals(document.querySelector('.screen[data-screen="B2"]'));
        };
      }
    }, 0);
  })();

  __DUNES_DIALOG_JS__
  (function patchNativeDialogs() {
    if (window.__dunesNativeDialogPatch) return;
    window.__dunesNativeDialogPatch = true;
    var nativeAlert = window.alert.bind(window);
    window.alert = function (msg) {
      if (window.DunesDialog && typeof window.DunesDialog.alert === 'function') {
        return window.DunesDialog.alert(msg == null ? '' : String(msg));
      }
      return nativeAlert(msg);
    };
    window.dunesConfirm = function (msg) {
      if (window.DunesDialog && typeof window.DunesDialog.confirm === 'function') {
        return window.DunesDialog.confirm(msg == null ? '' : String(msg));
      }
      return Promise.resolve(window.confirm(msg));
    };
  })();
  __DUNES_PROFILE_JS__
  (function initB2AfterProfileJs() {
    if (typeof readCachedProfile === 'function' && typeof applyUserProfile === 'function') {
      applyUserProfile(readCachedProfile());
    }
    if (typeof refreshUserProfile === 'function') refreshUserProfile();
    var active = document.querySelector('.screen.active');
    var sid = active && active.dataset ? active.dataset.screen : 'B2';
    if (sid === 'B2') {
      if (typeof loadB2Workbench === 'function') {
        Promise.race([
          loadB2Workbench().catch(function () {}),
          new Promise(function (resolve) { setTimeout(resolve, 12000); })
        ]);
      }
      else if (typeof window.__dunesRefreshRootTab === 'function') window.__dunesRefreshRootTab('B2');
    }
  })();
  __DUNES_CONTACTS_JS__
  __DUNES_INBOX_JS__
  __DUNES_NOVA_API_JS__
  __DUNES_IM_JS__
  __DUNES_KB_CHAT_JS__
  __DUNES_NOVA_JS__
  __DUNES_GROUP_JS__

  (function patchDunesApiNoti() {
    window.DunesApi = window.DunesApi || {};
    window.DunesApi.loadNotifications = function () {
      if (window.DunesInbox && typeof window.DunesInbox.loadZ2Notifications === 'function') {
        return window.DunesInbox.loadZ2Notifications();
      }
      return Promise.resolve();
    };
    window.DunesApi.loadConversations = function () {
      if (window.DunesInbox && typeof window.DunesInbox.loadC1 === 'function') {
        return window.DunesInbox.loadC1();
      }
      return Promise.resolve();
    };
    window.DunesApi.loadBroadcastList = function () {
      if (window.DunesInbox && typeof window.DunesInbox.loadBroadcastList === 'function') {
        return window.DunesInbox.loadBroadcastList();
      }
      return Promise.resolve();
    };
    window.DunesApi.wireC7Create = function () {
      if (window.DunesContacts && typeof window.DunesContacts.wireC7Create === 'function') {
        window.DunesContacts.wireC7Create();
      }
    };
    window.DunesApi.loadConvInfo = function () {
      if (window.DunesGroupInfo && typeof window.DunesGroupInfo.loadConvInfo === 'function') {
        return window.DunesGroupInfo.loadConvInfo();
      }
      return Promise.resolve();
    };
    window.DunesApi.loadConvMedia = function () {
      if (window.DunesGroupInfo && typeof window.DunesGroupInfo.loadConvMedia === 'function') {
        return window.DunesGroupInfo.loadConvMedia();
      }
      return Promise.resolve();
    };
    window.DunesApi.wireC4Assistant = function () {
      if (window.DunesNovaChat && typeof window.DunesNovaChat.onScreen === 'function') {
        window.DunesNovaChat.onScreen('C4');
      }
    };
  })();

  (function patchStackClicks() {
    var stack = document.getElementById('stack');
    if (!stack || stack.dataset.dunesClickPatched) return;
    stack.dataset.dunesClickPatched = '1';
    stack.addEventListener('click', function (e) {
      var kbChat = e.target.closest('[data-kb-chat]');
      if (kbChat) {
        e.preventDefault();
        e.stopPropagation();
        if (window.DunesKbChat && typeof window.DunesKbChat.guardKbEntry === 'function') {
          window.DunesKbChat.guardKbEntry({ kind: 'KB_ALL', from: 'C1' }).then(function (ok) {
            if (!ok) return;
            if (window.DunesApi && typeof window.DunesApi.enterKbChat === 'function') {
              window.DunesApi.enterKbChat({ kind: 'KB_ALL', from: 'C1' });
            } else if (typeof go === 'function') {
              window.pendingKbKind = 'KB_ALL';
              go('K2');
            }
          });
        } else if (window.DunesApi && typeof window.DunesApi.enterKbChat === 'function') {
          window.DunesApi.enterKbChat({ kind: 'KB_ALL', from: 'C1' });
        } else if (typeof go === 'function') {
          window.pendingKbKind = 'KB_ALL';
          go('K2');
        }
        return;
      }
      var goC4 = e.target.closest('[data-go="C4"]');
      if (goC4 && !goC4.hasAttribute('data-conv-id')) {
        var novaOnly = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
        if (!novaOnly) novaOnly = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
        if (novaOnly > 0) {
          window.pendingConvId = novaOnly;
          try { pendingConvId = novaOnly; } catch (e3) {}
        }
      }
      var t = e.target.closest('[data-conv-id],[data-peer-user-id],[data-contact-user-id]');
      if (!t) return;
      var cid = t.dataset.convId ? Number(t.dataset.convId) : 0;
      var pid = Number(t.dataset.peerUserId || t.dataset.contactUserId || 0);
      if (typeof window.__dunesSelectConversation === 'function') {
        window.__dunesSelectConversation(cid, pid);
        return;
      }
      if (t.dataset.contactUserId) window.pendingContactUserId = Number(t.dataset.contactUserId);
      else if (t.dataset.avatarUserId) window.pendingContactUserId = Number(t.dataset.avatarUserId);
      else if (t.dataset.peerUserId) window.pendingContactUserId = Number(t.dataset.peerUserId);
      if (t.dataset.peerUserId) window.__dunesPendingPeerUserId = Number(t.dataset.peerUserId);
      if (cid) {
        var goTarget = t.closest('[data-go]');
        if (goTarget && goTarget.dataset.go === 'C4') {
          var novaActive = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
          if (!novaActive) novaActive = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
          if (novaActive > 0) cid = novaActive;
          else if (window.DunesInbox && typeof window.DunesInbox.refreshNovaInboxPreview === 'function') {
            window.DunesInbox.refreshNovaInboxPreview();
          }
        }
        window.pendingConvId = cid;
        try { pendingConvId = cid; } catch (e2) {}
      }
    }, true);
  })();

  var ROOT_TABS = { C1: 1, QJ: 1, LH: 1, B2: 1 };
  function refreshRootTab(id) {
    if (!id || !ROOT_TABS[id]) return;
    if (id === 'B2') {
      if (window.DunesScreenLoader) window.DunesScreenLoader.show('B2', '加载中…');
      if (typeof refreshUserProfile === 'function') refreshUserProfile();
      var chain = Promise.resolve();
      if (typeof loadB2Workbench === 'function') {
        chain = loadB2Workbench().catch(function () {});
      } else if (window.WorkbenchLive && typeof WorkbenchLive.refreshMyBadgeFromServer === 'function') {
        chain = WorkbenchLive.refreshMyBadgeFromServer().catch(function () {});
      }
      chain = Promise.race([
        chain,
        new Promise(function (resolve) { setTimeout(resolve, 12000); })
      ]);
      chain.finally(function () {
        if (window.DunesScreenLoader) window.DunesScreenLoader.hide('B2');
      });
      if (typeof window.__dunesResetB2SoonVisuals === 'function') window.__dunesResetB2SoonVisuals();
    }
    if (id === 'C1') {
      if (window.DunesInbox && typeof DunesInbox.loadC1 === 'function') {
        Promise.race([
          DunesInbox.loadC1().catch(function () {}),
          new Promise(function (resolve) { setTimeout(resolve, 10000); })
        ]);
      } else if (window.DunesApi && typeof DunesApi.loadConversations === 'function') {
        Promise.race([
          DunesApi.loadConversations().catch(function () {}),
          new Promise(function (resolve) { setTimeout(resolve, 10000); })
        ]);
      }
      if (window.DunesInbox && typeof DunesInbox.refreshCommBadgeFromServer === 'function') {
        Promise.race([
          DunesInbox.refreshCommBadgeFromServer().catch(function () {}),
          new Promise(function (resolve) { setTimeout(resolve, 8000); })
        ]);
      }
    }
  }
  window.__dunesRefreshRootTab = refreshRootTab;

  var origSetScreen = typeof setScreen === 'function' ? setScreen : null;
  if (origSetScreen) {
    setScreen = function (id, back) {
      var prev = document.querySelector('.screen.active')?.dataset?.screen;
      var curScreen = document.querySelector('.screen.active');
      if (prev === 'C4' && (id === 'C11' || id === 'C12') && window.DunesNovaChat
        && typeof window.DunesNovaChat.isGenerationActive === 'function'
        && window.DunesNovaChat.isGenerationActive()) {
        return;
      }
      if (curScreen && curScreen.dataset && curScreen.dataset.screen === id && ROOT_TABS[id]) {
        refreshRootTab(id);
        return;
      }
      var finish = function () {
        if (prev === 'C4' && id !== 'C4' && window.DunesNovaChat && typeof window.DunesNovaChat.onLeave === 'function') {
          window.DunesNovaChat.onLeave();
        }
        if (prev === 'K2' && id !== 'K2' && window.DunesKbChat && typeof window.DunesKbChat.onLeave === 'function') {
          window.DunesKbChat.onLeave(prev);
        }
        if (prev === 'C12' && id !== 'C12') window.__dunesC12NovaMode = false;
        if ((prev === 'C2' || prev === 'C5' || prev === 'C13' || prev === 'C6') && id === 'C1') {
          window.pendingConvId = 0;
          try { pendingConvId = 0; } catch (e) {}
          window.__dunesActiveConvId = null;
        }
        if (id === 'C4') {
          var novaActive = Number(localStorage.getItem('dunes_nova_conv_id') || 0);
          if (novaActive > 0) {
            window.pendingConvId = novaActive;
            try { pendingConvId = novaActive; } catch (e) {}
          }
        }
        origSetScreen(id, back);
        if (ROOT_TABS[id]) refreshRootTab(id);
        if (id === 'C4' && typeof wireNovaC4 === 'function') wireNovaC4();
      if (window.DunesNovaChat && typeof window.DunesNovaChat.onScreen === 'function') {
        window.DunesNovaChat.onScreen(id);
      }
      if (window.DunesInbox && typeof window.DunesInbox.onScreen === 'function') {
        window.DunesInbox.onScreen(id);
      }
      if (window.DunesContacts && typeof window.DunesContacts.onScreen === 'function') {
        window.DunesContacts.onScreen(id);
      }
      if (window.DunesImChat && typeof window.DunesImChat.onScreen === 'function') {
        window.DunesImChat.onScreen(id);
      }
      if (window.DunesKbChat && typeof window.DunesKbChat.onScreen === 'function') {
        window.DunesKbChat.onScreen(id);
      }
      if (window.DunesGroupInfo && typeof window.DunesGroupInfo.onScreen === 'function') {
        window.DunesGroupInfo.onScreen(id);
      }
      if (id === 'B3' && window.XFlowDynamic && typeof window.XFlowDynamic.loadB3Templates === 'function') {
        window.XFlowDynamic.loadB3Templates();
      }
      if (id === 'XF' && window.XFlowDynamic && typeof window.XFlowDynamic.renderCurrentForm === 'function') {
        window.XFlowDynamic.renderCurrentForm();
      }
      try {
        if (window.DunesFlutterChannel) {
          window.DunesFlutterChannel.postMessage(JSON.stringify({
            type: 'screen',
            id: id,
            name: document.querySelector('.screen[data-screen="' + id + '"]')?.dataset?.name || id
          }));
        }
      } catch (e) {}
      };
      if ((prev === 'C5' || prev === 'C2') && id === 'C1' && window.DunesImChat && typeof window.DunesImChat.leaveChat === 'function') {
        window.DunesImChat.leaveChat().then(finish).catch(finish);
      } else {
        finish();
      }
    };
  }

  var origBack = typeof back === 'function' ? back : null;
  if (origBack) {
    back = function () {
      var leaving = document.querySelector('.screen.active')?.dataset?.screen;
      var markThenBack = function () {
        origBack();
        try {
          var id = document.querySelector('.screen.active')?.dataset?.screen;
          if (id && window.DunesFlutterChannel) {
            window.DunesFlutterChannel.postMessage(JSON.stringify({ type: 'screen', id: id }));
          }
          if (ROOT_TABS[id]) refreshRootTab(id);
          else if (id === 'C1' && window.DunesInbox) window.DunesInbox.loadC1();
          if ((id === 'C5' || id === 'C2') && window.DunesImChat) window.DunesImChat.onScreen(id);
        } catch (e) {}
      };
      if ((leaving === 'C5' || leaving === 'C2') && window.DunesImChat && typeof window.DunesImChat.leaveChat === 'function') {
        window.DunesImChat.leaveChat().then(markThenBack).catch(markThenBack);
      } else {
        markThenBack();
      }
    };
  }

  window.DunesFlutter = {
    go: function (id) {
      if (typeof go === 'function') go(id);
      else if (origSetScreen) origSetScreen(id, false);
    },
    back: function () {
      if (typeof back === 'function') back();
    },
    currentScreen: function () {
      return document.querySelector('.screen.active')?.dataset?.screen || 'B2';
    },
    openScreenIndex: function () {
      var fab = document.getElementById('fab');
      if (fab) fab.click();
    }
  };

  (function wirePullToRefresh() {
    if (window.__dunesPullRefreshWired) return;
    window.__dunesPullRefreshWired = true;
    var PTR = { startY: 0, pulling: false, activeEl: null, threshold: 72 };
    function activeScreenEl() {
      return document.querySelector('.screen.active');
    }
    function contentEl(screen) {
      return screen && screen.querySelector('.content');
    }
    function ensureIndicator(content) {
      if (!content) return null;
      var existing = content.parentElement && content.parentElement.querySelector('.dunes-ptr-indicator');
      if (existing) return existing;
      var wrap = content.parentElement;
      if (!wrap || !wrap.classList.contains('screen')) return null;
      if (getComputedStyle(wrap).position === 'static') wrap.style.position = 'relative';
      var el = document.createElement('div');
      el.className = 'dunes-ptr-indicator';
      el.innerHTML = '<div class="dunes-ptr-inner"><i class="ti ti-arrow-down"></i><span class="dunes-ptr-text">下拉刷新</span></div>';
      wrap.insertBefore(el, content);
      return el;
    }
    async function refreshActiveScreen() {
      var id = activeScreenEl()?.dataset?.screen || 'B2';
      if (ROOT_TABS[id]) {
        refreshRootTab(id);
        return;
      }
      var tasks = [];
      if (window.WorkbenchLive) {
        if (id === 'B1' && WorkbenchLive.loadB1ApprovalTodos) tasks.push(WorkbenchLive.loadB1ApprovalTodos());
        if (id === 'B14' && WorkbenchLive.loadB14Initiated) tasks.push(WorkbenchLive.loadB14Initiated());
        if (id === 'P1' && WorkbenchLive.loadCCProposals) tasks.push(WorkbenchLive.loadCCProposals());
        if (id === 'B3' && window.XFlowDynamic && XFlowDynamic.loadB3Templates) {
          try { window.XFlowDynamic.loadB3Templates(); } catch (e) {}
        }
      }
      if (window.DunesInbox && typeof DunesInbox.onScreen === 'function') {
        try { DunesInbox.onScreen(id); } catch (e) {}
      }
      if (window.DunesContacts && typeof DunesContacts.onScreen === 'function') {
        try { DunesContacts.onScreen(id); } catch (e) {}
      }
      if (window.DunesImChat && typeof DunesImChat.onScreen === 'function') {
        try { DunesImChat.onScreen(id); } catch (e) {}
      }
      if (window.DunesKbChat && typeof DunesKbChat.onScreen === 'function') {
        try { DunesKbChat.onScreen(id); } catch (e) {}
      }
      if (window.DunesNovaChat && typeof DunesNovaChat.onScreen === 'function') {
        try { DunesNovaChat.onScreen(id); } catch (e) {}
      }
      if (window.DunesGroupInfo && typeof DunesGroupInfo.onScreen === 'function') {
        try { DunesGroupInfo.onScreen(id); } catch (e) {}
      }
      await Promise.all(tasks.map(function (t) { return Promise.resolve(t).catch(function () {}); }));
    }
    window.__dunesRefreshActiveScreen = refreshActiveScreen;
    function resetPtr(content, indicator) {
      if (content) {
        content.classList.remove('dunes-ptr-pulling');
        content.style.transform = '';
      }
      if (indicator) {
        indicator.classList.remove('pulling', 'refreshing');
        indicator.style.height = '0px';
        var text = indicator.querySelector('.dunes-ptr-text');
        if (text) text.textContent = '下拉刷新';
        var icon = indicator.querySelector('.ti');
        if (icon) icon.className = 'ti ti-arrow-down';
      }
      PTR.pulling = false;
      PTR.activeEl = null;
    }
    document.addEventListener('touchstart', function (ev) {
      var content = contentEl(activeScreenEl());
      if (!content || ev.touches.length !== 1) return;
      if ((content.scrollTop || 0) > 2) return;
      PTR.startY = ev.touches[0].clientY;
      PTR.activeEl = content;
      PTR.pulling = false;
    }, { passive: true });
    document.addEventListener('touchmove', function (ev) {
      if (!PTR.activeEl || ev.touches.length !== 1) return;
      var dy = ev.touches[0].clientY - PTR.startY;
      if (dy <= 0) {
        if (PTR.pulling) resetPtr(PTR.activeEl, ensureIndicator(PTR.activeEl));
        return;
      }
      if ((PTR.activeEl.scrollTop || 0) > 2) return;
      PTR.pulling = true;
      var indicator = ensureIndicator(PTR.activeEl);
      if (!indicator) return;
      var h = Math.min(96, dy * 0.45);
      indicator.style.height = h + 'px';
      indicator.classList.add('pulling');
      PTR.activeEl.classList.add('dunes-ptr-pulling');
      PTR.activeEl.style.transform = 'translateY(' + Math.min(36, dy * 0.25) + 'px)';
      var text = indicator.querySelector('.dunes-ptr-text');
      var icon = indicator.querySelector('.ti');
      if (text) text.textContent = dy >= PTR.threshold ? '松开刷新' : '下拉刷新';
      if (icon) icon.className = dy >= PTR.threshold ? 'ti ti-refresh' : 'ti ti-arrow-down';
      if (dy > 12) ev.preventDefault();
    }, { passive: false });
    document.addEventListener('touchend', function () {
      if (!PTR.activeEl) return;
      var content = PTR.activeEl;
      var indicator = ensureIndicator(content);
      var text = indicator && indicator.querySelector('.dunes-ptr-text');
      var shouldRefresh = PTR.pulling && text && text.textContent === '松开刷新';
      if (!shouldRefresh) {
        resetPtr(content, indicator);
        return;
      }
      if (indicator) {
        indicator.classList.add('refreshing');
        indicator.style.height = '52px';
        if (text) text.textContent = '刷新中…';
      }
      refreshActiveScreen().catch(function () {}).finally(function () {
        resetPtr(content, indicator);
      });
    }, { passive: true });
  })();

  setTimeout(function () {
    if (typeof refreshUserProfile === 'function') refreshUserProfile();
    if (typeof wireNovaC4 === 'function') wireNovaC4();
    if (typeof window.patchNovaIcons === 'function') window.patchNovaIcons();
    if (window.DunesNovaApi && typeof window.DunesNovaApi.ensureNovaProfileSession === 'function') {
      window.DunesNovaApi.ensureNovaProfileSession();
    }
    if (window.DunesNovaChat && typeof window.DunesNovaChat.prefetchServerHistory === 'function') {
      window.DunesNovaChat.prefetchServerHistory().then(function () {
        if (window.DunesInbox && typeof window.DunesInbox.refreshNovaInboxPreview === 'function') {
          window.DunesInbox.refreshNovaInboxPreview();
        }
      }).catch(function () {});
    }
    var active = document.querySelector('.screen.active')?.dataset?.screen || 'B2';
    if (window.DunesInbox && typeof window.DunesInbox.refreshCommBadgeFromServer === 'function') {
      window.DunesInbox.refreshCommBadgeFromServer();
    }
    if (window.WorkbenchLive && typeof window.WorkbenchLive.refreshMyBadgeFromServer === 'function') {
      window.WorkbenchLive.refreshMyBadgeFromServer();
    }
    if (window.DunesInbox && typeof window.DunesInbox.onScreen === 'function') {
      window.DunesInbox.onScreen(active);
    }
    if (window.DunesContacts && typeof window.DunesContacts.onScreen === 'function') {
      window.DunesContacts.onScreen(active);
    }
    if (window.DunesImChat && typeof window.DunesImChat.onScreen === 'function') {
      window.DunesImChat.onScreen(active);
    }
    if (window.DunesNovaChat && typeof window.DunesNovaChat.onScreen === 'function') {
      window.DunesNovaChat.onScreen(active);
    }
    if (window.DunesKbChat && typeof window.DunesKbChat.onScreen === 'function') {
      window.DunesKbChat.onScreen(active);
    }
    if (window.DunesGroupInfo && typeof window.DunesGroupInfo.onScreen === 'function') {
      window.DunesGroupInfo.onScreen(active);
    }
    if (window.DunesFlutterChannel) {
      window.DunesFlutterChannel.postMessage(JSON.stringify({ type: 'ready', id: active }));
    }
  }, 120);
})();
''';

  static const prototypeBaseUrl = 'https://app.dunes.local/';

  static String novaStorageBridgeScript() {
    return r'''
(function () {
  var EXACT = {
    'dunes_nova_conv_id': 1,
    'dunes_nova_profile_session': 1,
    'dunes_nova_local_history': 1,
    'dunes_nova_chat_model': 1,
    'dunes_nova_view_since': 1,
    'dunes_nova_history_sync_queue': 1,
    'dunes_ai_local_purge_v': 1,
    'dunes_kb_local_history': 1,
    'dunes_kb_conv_id': 1,
    'dunes_kb_last_preview': 1
  };
  var PREFIX = ['dunes_nova_msgs_', 'dunes_kb_msgs_'];
  function shouldPersist(key) {
    if (!key) return false;
    if (EXACT[key]) return true;
    for (var i = 0; i < PREFIX.length; i++) {
      if (key.indexOf(PREFIX[i]) === 0) return true;
    }
    return false;
  }
  function collectNovaPersistState() {
    var out = {};
    Object.keys(EXACT).forEach(function (k) {
      try {
        var v = localStorage.getItem(k);
        if (v != null && v !== '') out[k] = v;
      } catch (e) {}
    });
    try {
      for (var i = 0; i < localStorage.length; i++) {
        var k = localStorage.key(i);
        if (!k || !shouldPersist(k) || EXACT[k]) continue;
        var val = localStorage.getItem(k);
        if (val != null && val !== '') out[k] = val;
      }
    } catch (e2) {}
    return out;
  }
  function emitNovaPersistState() {
    var data = collectNovaPersistState();
    var payload = JSON.stringify({ type: 'nova-storage', data: data });
    try {
      if (window.DunesFlutterChannel && window.DunesFlutterChannel.postMessage) {
        window.DunesFlutterChannel.postMessage(payload);
      }
    } catch (e) {}
    try {
      parent.postMessage({ source: 'dunes-prototype', type: 'nova-storage', data: data }, '*');
    } catch (e2) {}
  }
  function scheduleNovaPersist() {
    clearTimeout(window.__dunesNovaPersistTimer);
    window.__dunesNovaPersistTimer = setTimeout(emitNovaPersistState, 500);
  }
  window.__dunesScheduleNovaPersist = scheduleNovaPersist;
  window.__dunesEmitNovaPersistState = emitNovaPersistState;
  try {
    var _setItem = localStorage.setItem.bind(localStorage);
    localStorage.setItem = function (k, v) {
      _setItem(k, v);
      if (shouldPersist(k)) scheduleNovaPersist();
    };
    var _removeItem = localStorage.removeItem.bind(localStorage);
    localStorage.removeItem = function (k) {
      _removeItem(k);
      if (shouldPersist(k)) scheduleNovaPersist();
    };
  } catch (e3) {}
  window.addEventListener('pagehide', emitNovaPersistState);
  if (window.DunesNovaApi && typeof window.DunesNovaApi.ensureNovaProfileSession === 'function') {
    window.DunesNovaApi.ensureNovaProfileSession();
  }
})();
''';
  }

  static String bootstrapScript() {
    return NovaConfig.bindNovaBase(
      DunesDefaults.bindApiBase(
        bootstrapJs
            .replaceAll('__DUNES_CSS__', _escapeJsString(css))
            .replaceAll('__DUNES_DIALOG_JS__', _dialogJs)
            .replaceAll('__DUNES_PROFILE_JS__', _profileJs)
            .replaceAll('__DUNES_CONTACTS_JS__', _contactsJs)
            .replaceAll('__DUNES_INBOX_JS__', _inboxJs)
            .replaceAll('__DUNES_NOVA_API_JS__', NovaApiInjection.js)
            .replaceAll('__DUNES_IM_JS__', ImChatInjection.js)
            .replaceAll('__DUNES_KB_CHAT_JS__', KbChatInjection.js)
            .replaceAll('__DUNES_NOVA_JS__', NovaChatInjection.js)
            .replaceAll('__DUNES_GROUP_JS__', _groupInfoJs),
      ),
    );
  }

  static String profileScript() => _profileJs;

  /// centrifuge.js 源码（bootstrap 前注入，避免 srcdoc 无法加载外部脚本）。
  static Future<String> centrifugeScript() async {
    return rootBundle.loadString('assets/prototype/centrifuge.js');
  }

  /// Tabler Icons 内联样式（避免 srcdoc / 离线环境 CDN 加载失败导致全局小图标消失）。
  static String? _tablerIconsStyleCache;
  static bool _tablerIconsStyleFailed = false;

  static Future<String?> tablerIconsStyle() async {
    if (_tablerIconsStyleFailed) return null;
    if (_tablerIconsStyleCache != null) return _tablerIconsStyleCache;
    try {
      final css = await rootBundle.loadString(
        'assets/prototype/tabler-icons.min.css',
      );
      final fontBytes = await rootBundle.load(
        'assets/prototype/tabler-icons.woff2',
      );
      final fontUri =
          'data:font/woff2;base64,${base64Encode(fontBytes.buffer.asUint8List())}';
      final inlined = css
          .replaceAll(
            RegExp(r'url\("\./fonts/tabler-icons\.woff2[^"]*"\)'),
            'url("$fontUri")',
          )
          .replaceAll(
            RegExp(r'url\("\./fonts/tabler-icons\.woff[^"]*"\)'),
            'url("$fontUri")',
          )
          .replaceAll(
            RegExp(r'url\("\./fonts/tabler-icons\.ttf[^"]*"\)'),
            'url("$fontUri")',
          );
      _tablerIconsStyleCache =
          '<style id="dunes-tabler-icons">$inlined</style>';
      return _tablerIconsStyleCache;
    } catch (_) {
      _tablerIconsStyleFailed = true;
      return null;
    }
  }

  static Future<String> _loadAsset(String path) =>
      rootBundle.loadString('assets/prototype/$path');

  /// Flutter WebView / blob 无法加载相对路径 script src，须内联 XFlow 资源。
  static Future<String> inlineXFlowAssets(String html) async {
    final appUi = await _loadAsset('dunes_app_ui.js');
    final workbenchLive = await _loadAsset('workbench_live.js');
    final linkage = await _loadAsset('xflow_linkage.js');
    final render = await _loadAsset('xflow_render.js');
    final detail = await _loadAsset('xflow_detail.js');
    final dynamic = await _loadAsset('xflow_dynamic.js');
    final fieldsCss = await _loadAsset('xflow_fields.css');
    var out = html;
    if (out.contains('<head>')) {
      out = out.replaceFirst(
        '<head>',
        '<head><style id="xf-fields-css">$fieldsCss</style>',
      );
    }
    out = out.replaceFirst(
      '<script src="dunes_app_ui.js"></script>',
      '<script>$appUi</script>',
    );
    const workbenchTag = '<script src="workbench_live.js"></script>';
    if (out.contains(workbenchTag)) {
      out = out.replaceFirst(
        workbenchTag,
        '<script>$workbenchLive</script>',
      );
    } else if (out.contains('<script src="xflow_linkage.js"></script>')) {
      out = out.replaceFirst(
        '<script src="xflow_linkage.js"></script>',
        '<script>$workbenchLive</script>\n<script src="xflow_linkage.js"></script>',
      );
    }
    out = out.replaceFirst(
      '<script src="xflow_linkage.js"></script>',
      '<script>$linkage</script>',
    );
    out = out.replaceFirst(
      '<script src="xflow_render.js"></script>',
      '<script>$render</script>',
    );
    out = out.replaceFirst(
      '<script src="xflow_detail.js"></script>',
      '<script>$detail</script>',
    );
    out = out.replaceFirst(
      '<script src="xflow_dynamic.js"></script>',
      '<script>$dynamic</script>',
    );
    return out;
  }

  static Future<String> preparePrototypeHtml(
    String html, {
    String? token,
    String? apiBase,
    int? userId,
    String? displayName,
    String? phone,
    List<String>? roles,
    Map<String, String>? novaLocalStorage,
    Map<String, String>? novaWebStorage,
  }) async {
    final iconBytes = await rootBundle.load('assets/prototype/nova-icon.png');
    final iconDataUri =
        'data:image/png;base64,${base64Encode(iconBytes.buffer.asUint8List())}';
    final iconScript =
        "<script>window.__dunesNovaIconSrc=${_escapeJsString(iconDataUri)};</script>";
    final tablerStyle = await tablerIconsStyle();
    var result = injectAuthPrelude(
      html,
      token: token,
      apiBase: apiBase,
      userId: userId,
      displayName: displayName,
      phone: phone,
      roles: roles,
      novaLocalStorage: novaLocalStorage,
      novaWebStorage: novaWebStorage,
    );
    if (result.contains('<head>')) {
      result = result.replaceFirst(
        '<head>',
        '<head>$iconScript${tablerStyle ?? ''}',
      );
    } else {
      result = '$iconScript${tablerStyle ?? ''}$result';
    }
    if (tablerStyle != null) {
      result = result.replaceFirst(
        RegExp(
          r'<link rel="stylesheet" href="https://cdn\.jsdelivr\.net/npm/@tabler/icons-webfont[^"]+">',
        ),
        '',
      );
    }
    result = await inlineXFlowAssets(result);
    result = DunesDefaults.bindApiBase(result);
    return applyAppShellMode(result);
  }

  /// 在 HTML 解析阶段就进入 App 全屏模式，避免先闪出原型介绍页（hero）。
  static String applyAppShellMode(String html) {
    var result = html;
    if (result.contains('<head>')) {
      result = result.replaceFirst(
        '<head>',
        '<head><style id="dunes-flutter-shell">$css</style>',
      );
    }
    if (result.contains('<body class="flutter-app-mode">')) {
      return result;
    }
    if (result.contains('<body>')) {
      result = result.replaceFirst('<body>', '<body class="flutter-app-mode">');
    } else {
      result = result.replaceFirst('<body ', '<body class="flutter-app-mode" ');
    }
    return result;
  }

  static String injectAuthPrelude(
    String html, {
    String? token,
    String? apiBase,
    int? userId,
    String? displayName,
    String? phone,
    List<String>? roles,
    Map<String, String>? novaLocalStorage,
    Map<String, String>? novaWebStorage,
  }) {
    final script =
        '<script>${authScript(token: token, apiBase: apiBase, userId: userId, displayName: displayName, phone: phone, roles: roles, novaLocalStorage: novaLocalStorage, novaWebStorage: novaWebStorage)}</script>';
    if (html.contains('<head>')) {
      return html.replaceFirst('<head>', '<head>$script');
    }
    return '$script$html';
  }

  static String? _wsBaseFromApi(String? apiBase) {
    if (apiBase == null || apiBase.isEmpty) return null;
    final http = apiBase.replaceAll(RegExp(r'/api/v1/?$'), '');
    final ws = http.replaceFirst('http', 'ws');
    return '$ws/connection/websocket';
  }

  static String _flowApiBaseFromApi(String? apiBase) {
    if (apiBase == null || apiBase.isEmpty) return DunesDefaults.flowApiBase;
    final uri = Uri.tryParse(apiBase);
    if (uri == null || uri.host.isEmpty) return DunesDefaults.flowApiBase;
    return uri
        .replace(port: DunesDefaults.flowPort, path: '/api/v1')
        .toString();
  }

  static String authScript({
    String? token,
    String? apiBase,
    int? userId,
    String? displayName,
    String? phone,
    List<String>? roles,
    Map<String, String>? novaLocalStorage,
    Map<String, String>? novaWebStorage,
  }) {
    final wsBase = _wsBaseFromApi(apiBase);
    final roleList = roles;
    final entries = <String, String>{};
    if (novaWebStorage != null) entries.addAll(novaWebStorage);
    entries['dunes_nova_base'] =
        novaLocalStorage?['dunes_nova_base'] ?? NovaConfig.baseUrl;
    if (novaLocalStorage != null) entries.addAll(novaLocalStorage);
    if (token != null && token.isNotEmpty) {
      entries['dunes_token'] = token;
      entries['dunes_jwt'] = token;
    }
    if (apiBase != null && apiBase.isNotEmpty) {
      entries['dunes_api_base'] = apiBase;
      entries['dunes_flow_api_base'] = _flowApiBaseFromApi(apiBase);
    } else {
      entries['dunes_flow_api_base'] = DunesDefaults.flowApiBase;
    }
    if (wsBase != null) entries['dunes_ws_base'] = wsBase;
    if (userId != null) entries['dunes_user_id'] = '$userId';
    if (displayName != null && displayName.isNotEmpty) {
      entries['dunes_display_name'] = displayName;
    }
    if (phone != null && phone.isNotEmpty) entries['dunes_phone'] = phone;
    if (roleList != null && roleList.isNotEmpty) {
      entries['dunes_roles'] = jsonEncode(roleList);
    }
    final writes = entries.entries
        .map(
          (e) =>
              "localStorage.setItem('${e.key}', ${_escapeJsString(e.value)});",
        )
        .join();
    final windowApiBase = (apiBase != null && apiBase.isNotEmpty)
        ? 'window.__dunesApiBase=${_escapeJsString(apiBase)};'
        : '';
    final windowNovaBase =
        "window.__dunesNovaBase=${_escapeJsString(entries['dunes_nova_base'] ?? NovaConfig.baseUrl)};";
    final windowNovaKey = entries['dunes_nova_api_key'];
    final windowNovaKeyWrite = windowNovaKey != null && windowNovaKey.isNotEmpty
        ? 'window.__dunesNovaApiKey=${_escapeJsString(windowNovaKey)};'
        : '';
    return 'try{$windowApiBase$windowNovaBase$windowNovaKeyWrite$writes;${novaStorageBridgeScript()}}catch(e){}';
  }

  static String _escapeJsString(String s) {
    return "'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n').replaceAll('\r', '')}'";
  }

  static String goToScreen(String screenId) =>
      "window.DunesFlutter && window.DunesFlutter.go('$screenId');";

  static String goBack() =>
      "window.DunesFlutter && window.DunesFlutter.back();";

  static String currentScreen() =>
      "window.DunesFlutter ? window.DunesFlutter.currentScreen() : 'B2';";
}
