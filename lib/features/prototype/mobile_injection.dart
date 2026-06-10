import 'dart:convert';

import 'package:flutter/services.dart';

import '../im/im_chat_injection.dart';
import '../im/kb_chat_injection.dart';
import '../im/nova_chat_injection.dart';

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
.flutter-app-mode .screen[data-screen="C4"] .ai-prompts {
  flex-shrink: 0 !important;
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
.flutter-app-mode .screen[data-screen="C4"] .msg-quick-actions {
  display: grid !important;
  grid-template-columns: repeat(6, minmax(0, 1fr)) !important;
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
.flutter-app-mode .chat-conv-header.private .cv-av-mini { position: relative; }
.flutter-app-mode .chat-conv-header.private .cv-av-mini .av-dot {
  position: absolute; bottom: -1px; right: -1px;
  width: 9px; height: 9px; border-radius: 50%;
  background: #22A47D; border: 2px solid var(--bg-app);
  display: none;
}
.flutter-app-mode .chat-conv-header.private .cv-av-mini .av-dot.on { display: block; }
.flutter-app-mode .dunes-jump-latest {
  position: sticky;
  bottom: 8px;
  z-index: 6;
  display: flex;
  justify-content: center;
  padding: 6px 0 4px;
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
.flutter-app-mode #c1-conv-list:not(.dunes-api-ready) > * { display: none !important; }
.flutter-app-mode #c1-conv-list.dunes-api-ready:empty::before {
  content: '加载会话…';
  display: block;
  padding: 24px 16px;
  color: var(--text-3);
  font-size: 12px;
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
.flutter-app-mode .screen[data-screen="C3"] .dept-tree > :not(.dept-block) {
  display: none !important;
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
.flutter-app-mode .screen[data-screen="C12"] .action-bar {
  display: none !important;
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
  align-items: center;
  gap: 6px;
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
  flex: 1;
  font-size: 11px;
  color: var(--text-3);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
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
  color: var(--text-4);
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
  var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
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
function applyUserProfile(p) {
  if (!p) return;
  var screen = document.querySelector('.screen[data-screen="B2"]');
  if (!screen) return;
  var avatar = screen.querySelector('.profile-head .avatar');
  var nm = screen.querySelector('.profile-head .nm');
  var rl = screen.querySelector('.profile-head .rl');
  var badges = screen.querySelector('.profile-head .badges');
  var name = p.displayName || '';
  renderProfileAvatar(avatar, p);
  if (nm && name) nm.textContent = name;
  if (rl) {
    var parts = [];
    if (p.departmentName) parts.push(p.departmentName);
    if (p.title) parts.push(p.title);
    if (p.phone) parts.push(maskPhone(p.phone));
    rl.textContent = parts.filter(Boolean).join(' · ');
  }
  if (badges) {
    var labels = p.roleLabels || p.roles || [];
    if (labels.length) {
      badges.innerHTML = labels.map(function (r, i) {
        var label = typeof r === 'string' ? r : (r.name || r.code || r);
        var cls = i === 0 ? 'rb role' : 'rb';
        return '<span class="' + cls + '">' + label + '</span>';
      }).join('');
    } else {
      badges.innerHTML = '<span class="rb role">员工</span>';
    }
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
  var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
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
  var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
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
  var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
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
    }
  } catch (e) {}
}
window.__dunesRefreshUserProfile = refreshUserProfile;

function wireNovaC4() {
  var NOVA_INTRO = '你好，我是你的 NOVA 助手';
  var NOVA_HEAD = 'NOVA <span class="group-tag" style="background:linear-gradient(135deg,#FFD580,#FFA850);color:#5D3508">AI</span>';
  var screen = document.querySelector('.screen[data-screen="C4"]');
  if (!screen) return;
  screen.dataset.name = 'NOVA';
  document.querySelectorAll('.screen[data-screen="C4"] .cv-nm').forEach(function (el) {
    el.innerHTML = NOVA_HEAD;
  });
  document.querySelectorAll('.screen[data-screen="C4"] .ah-nm').forEach(function (el) {
    el.innerHTML = 'NOVA<span class="badge-ai">AI</span>';
  });
  document.querySelectorAll('.screen[data-screen="C4"] .msg-meta .nm').forEach(function (el) {
    if (el.textContent.indexOf('沙丘助手') >= 0 || el.textContent.indexOf('NOVA') >= 0) el.textContent = 'NOVA';
  });
  var panel = document.getElementById('c4-ai-prompts') || screen.querySelector('.ai-prompts');
  if (panel && !panel.id) panel.id = 'c4-ai-prompts';
  var toggle = document.getElementById('c4-prompts-toggle') || (panel && panel.querySelector('.ap-h'));
  if (toggle && !toggle.id) toggle.id = 'c4-prompts-toggle';
  if (toggle && !toggle.querySelector('.ap-chev')) {
    toggle.insertAdjacentHTML('beforeend', '<i class="ti ti-chevron-down ap-chev"></i>');
  }
  if (toggle) {
    toggle.setAttribute('role', 'button');
    toggle.setAttribute('tabindex', '0');
  }
  function flipC4Prompts(open) {
    var p = document.getElementById('c4-ai-prompts');
    if (!p) return;
    var next = open !== undefined ? !!open : !p.classList.contains('expanded');
    p.classList.toggle('expanded', next);
    p.classList.remove('collapsed');
    var grid = p.querySelector('.ai-prompts-grid');
    if (grid) {
      if (next) grid.style.removeProperty('display');
      else grid.style.display = 'none';
    }
    var t = document.getElementById('c4-prompts-toggle');
    if (t) t.setAttribute('aria-expanded', next ? 'true' : 'false');
  }
  window.__dunesFlipC4Prompts = flipC4Prompts;
  if (!screen.dataset.c4PromptsToggleWired) {
    screen.dataset.c4PromptsToggleWired = '1';
    screen.addEventListener('click', function (e) {
      var hit = e.target.closest('#c4-prompts-toggle, #c4-ai-prompts > .ap-h');
      if (!hit) return;
      e.preventDefault();
      e.stopPropagation();
      flipC4Prompts();
    }, true);
    if (toggle) {
      toggle.addEventListener('keydown', function (e) {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); flipC4Prompts(); }
      });
    }
  }
  flipC4Prompts(false);
  document.querySelectorAll('.screen[data-screen="C4"] .ah-av').forEach(function (el) {
    if (window.dunesNovaIconHtml) el.innerHTML = window.dunesNovaIconHtml();
  });
  if (typeof window.patchNovaIcons === 'function') window.patchNovaIcons();
  window.__dunesNovaIntro = NOVA_INTRO;
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
  function apiFetch(path, opts) {
    opts = opts || {};
    var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var headers = Object.assign({}, opts.headers || {});
    if (token) headers.Authorization = 'Bearer ' + token;
    if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    return fetch(base + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body || undefined
    }).then(function (r) { return r.json(); });
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
    var role = c.title || (c.roleCodes && c.roleCodes[0]) || '';
    var dept = c.department || '';
    return ''
      + '<div class="contact-row tappable" data-go="C9" data-contact-user-id="' + uid + '">'
      + '<div class="cr-av ' + personCls(uid) + '">' + esc((c.displayName || '?').slice(0, 1)) + '<div class="av-dot"></div></div>'
      + '<div class="ct-bd"><div class="ct-nm">' + esc(c.displayName || '') + me + '</div>'
      + '<div class="ct-meta"><span class="role">' + esc(role) + '</span><span>id=' + uid + '</span><span>' + esc(dept) + '</span></div></div>'
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
  function renderDeptBlock(dep, pickMode) {
    var exp = !!dep.expanded;
    var head = ''
      + '<div class="dept-head' + (exp ? ' expanded' : '') + '">'
      + '<i class="ti ti-chevron-right dh-chev"></i>'
      + '<div class="dh-ic"><i class="ti ti-building"></i></div>'
      + '<div class="dh-bd"><div class="dh-nm">' + esc(dep.name || '部门') + '</div>'
      + '<div class="dh-sub">' + esc(dep.code || '') + '</div></div>'
      + '<div class="dh-cnt">' + (dep.userCount || (dep.users && dep.users.length) || 0) + '</div></div>';
    var peopleHtml = '';
    (dep.users || []).forEach(function (c) {
      peopleHtml += pickMode ? renderPickRow(c) : renderContactRow(c);
    });
    var people = '<div class="dept-people"' + (exp ? '' : ' style="display:none"') + '>' + peopleHtml + '</div>';
    var childHtml = '';
    (dep.children || []).forEach(function (ch) {
      childHtml += renderDeptBlock(ch, pickMode);
    });
    var children = childHtml
      ? '<div class="dept-children"' + (exp ? '' : ' style="display:none"') + '>' + childHtml + '</div>'
      : '';
    return '<div class="dept-block" data-api-dept="1" data-dept-id="' + (dep.id || 0) + '">' + head + people + children + '</div>';
  }
  function renderPickRow(c) {
    var uid = Number(c.userId);
    if (!uid || uid === devUserId()) return '';
    var on = window.c7SelectedIds && window.c7SelectedIds.has(uid) ? ' on' : '';
    return '<div class="contact-pick-row tappable' + on + '" data-pick-user-id="' + uid + '">'
      + '<div class="cp-check"><i class="ti ti-check"></i></div>'
      + '<div class="cp-av ' + personCls(uid) + '">' + esc((c.displayName || '?').slice(0, 1)) + '</div>'
      + '<div class="cp-bd"><div class="cp-nm">' + esc(c.displayName || '') + '</div>'
      + '<div class="cp-m"><span>' + esc(c.title || '') + '</span><span>' + esc(c.department || '') + '</span></div></div></div>';
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
  function wireC7PickRows(root) {
    if (!root) return;
    root.querySelectorAll('[data-pick-user-id]').forEach(function (row) {
      if (row.dataset.wiredPick) return;
      row.dataset.wiredPick = '1';
      row.addEventListener('click', function () {
        var uid = Number(row.getAttribute('data-pick-user-id'));
        if (!uid) return;
        if (!window.c7SelectedIds) window.c7SelectedIds = new Set();
        if (window.c7Mode === 'private') {
          window.c7SelectedIds.clear();
          root.querySelectorAll('.contact-pick-row.on').forEach(function (r) { r.classList.remove('on'); });
        }
        if (window.c7SelectedIds.has(uid)) {
          window.c7SelectedIds.delete(uid);
          row.classList.remove('on');
        } else {
          window.c7SelectedIds.add(uid);
          row.classList.add('on');
        }
        updateC7SelectedStack();
      });
    });
  }
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
    document.querySelectorAll('.screen[data-screen="C7"] .new-conv-kinds .nck').forEach(function (nck, idx) {
      if (nck.dataset.wiredNck) return;
      nck.dataset.wiredNck = '1';
      nck.classList.add('tappable');
      nck.addEventListener('click', function () {
        document.querySelectorAll('.screen[data-screen="C7"] .new-conv-kinds .nck').forEach(function (x) {
          x.classList.remove('featured');
        });
        nck.classList.add('featured');
        window.c7Mode = idx === 0 ? 'group' : 'private';
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
      tree.innerHTML = '';
      if (q) {
        if (!items.length) {
          tree.innerHTML = '<div class="api-strip"><span>无匹配联系人</span></div>';
          return;
        }
        items.forEach(function (c) {
          tree.insertAdjacentHTML('beforeend', renderContactRow(c));
        });
        wireMsgButtons(tree);
        c3Loaded = true;
        c3LastQuery = q;
        restoreC3Scroll();
        refreshOnlineDots();
        return;
      }
      if (!depts.length) {
        tree.innerHTML = '<div class="api-strip"><span>暂无组织数据 · 请确认 im-go / flow-go 已启动</span></div>';
        return;
      }
      depts.forEach(function (dep) {
        tree.insertAdjacentHTML('beforeend', renderDeptBlock(dep, false));
      });
      wireDeptToggle(tree);
      wireMsgButtons(tree);
      c3Loaded = true;
      c3LastQuery = q || '';
      restoreC3Scroll();
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
      box.innerHTML = '';
      if (q) {
        if (!items.length) {
          box.innerHTML = '<div class="api-strip"><span>无匹配联系人</span></div>';
          return;
        }
        items.forEach(function (c) {
          box.insertAdjacentHTML('beforeend', renderPickRow(c));
        });
      } else if (!depts.length) {
        box.innerHTML = '<div class="api-strip"><span>暂无组织数据</span></div>';
        return;
      } else {
        depts.forEach(function (dep) {
          box.insertAdjacentHTML('beforeend', renderDeptBlock(dep, true));
        });
      }
      var mock = document.getElementById('c7-mock-contacts');
      if (mock) mock.style.display = 'none';
      wireDeptToggle(box);
      wireC7PickRows(box);
      updateC7SelectedStack();
      refreshOnlineDots();
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
      if (uid && online[String(uid)]) dot.classList.add('on');
      else dot.classList.remove('on');
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
      loadC7('');
    }
    if (id === 'C9') {
      var uid = Number(window.pendingContactUserId || 0);
      if (window.DunesApi && typeof window.DunesApi.loadContactDetail === 'function') {
        window.DunesApi.loadContactDetail(uid);
      }
      if (window.DunesPresence && typeof window.DunesPresence.refreshC9 === 'function') {
        window.DunesPresence.refreshC9();
      }
    }
  }
  return {
    onScreen: onScreen,
    loadC3: loadC3,
    loadC7: loadC7,
    wireC7Create: wireC7Create,
    createC7Conversation: createC7Conversation,
    refreshOnlineDots: refreshOnlineDots
  };
})();
''';

  /// C1 消息首页：用 im-go `/conversations` + `/notifications` 渲染，替换静态 mock 行（不改 UI 样式类名）。
  static const _inboxJs = r'''
window.DunesInbox = (function () {
  var searchWired = false;
  var _c1RefreshTimer = null;
  var _c1Loaded = false;
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
  function apiFetch(path, opts) {
    opts = opts || {};
    var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var headers = Object.assign({}, opts.headers || {});
    if (token) headers.Authorization = 'Bearer ' + token;
    if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    return fetch(base + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body || undefined
    }).then(function (r) { return r.json(); });
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
    var seed = peerId || Number(c.id);
    var initial = (peerName || '?').slice(0, 1);
    var tm = formatTimeDetailed(c.lastMessageAt, true);
    var preview = esc(c.lastMessagePreview || '');
    var meta = c.unreadCount
      ? '<div class="cr-meta"><span class="badge-num accent">' + c.unreadCount + '</span></div>'
      : '';
    var sub = c.peerTitle || c.peerRoleLabel || '';
    return '<div class="chat-row tappable" data-go="C5" data-conv-id="' + c.id + '" data-peer-user-id="' + peerId + '" data-contact-user-id="' + peerId + '" data-last-at="' + esc(c.lastMessageAt || '') + '">'
      + '<div class="cr-av ' + personCls(seed) + '" data-open-contact="1">' + esc(initial) + '<div class="av-dot"></div></div>'
      + '<div class="cr-bd"><div class="cr-top"><div class="cr-nm">' + esc(peerName)
      + deptTitleHtml(c.peerDepartment, sub) + '</div><div class="cr-tm">' + esc(tm) + '</div></div>'
      + '<div class="cr-pv">' + preview + '</div></div>' + meta + '</div>';
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
  var NOVA_INTRO = '你好，我是你的 NOVA 助手';
  function assistantDisplayTitle(c) {
    // 通讯列表固定展示 NOVA；会话 title 仅用于 C11 历史列表区分多轮对话
    return 'NOVA';
  }
  function assistantPreview(text) {
    var s = String(text || '');
    if (!s || s.indexOf('沙丘助手') >= 0 || /^你好/.test(s)) return NOVA_INTRO;
    return s;
  }
  function novaGeneratingPreviewHtml(status) {
    var s = esc(status || '正在生成…');
    return '<span class="generating"><i class="ti ti-loader ti-spin"></i> ' + s + '</span>';
  }
  function novaConvPreview(c) {
    if (c.assistantGenerating) {
      return novaGeneratingPreviewHtml(c.assistantGeneratingStatus);
    }
    return esc(assistantPreview(c.lastMessagePreview));
  }
  function patchNovaGeneratingPreview(convId, generating, status, normalPreview) {
    if (!convId) return;
    var list = document.getElementById('c1-conv-list');
    if (!list || !list.classList.contains('dunes-api-ready')) return;
    var row = list.querySelector('.chat-row[data-conv-id="' + convId + '"]');
    if (!row) return;
    var pv = row.querySelector('.cr-pv');
    if (!pv) return;
    if (generating) {
      if (!row.dataset.previewNormal) row.dataset.previewNormal = pv.innerHTML;
      pv.innerHTML = novaGeneratingPreviewHtml(status);
      row.classList.add('nova-generating');
      return;
    }
    row.classList.remove('nova-generating');
    if (normalPreview != null && normalPreview !== '') {
      pv.innerHTML = esc(assistantPreview(normalPreview));
      delete row.dataset.previewNormal;
    } else if (row.dataset.previewNormal) {
      pv.innerHTML = row.dataset.previewNormal;
      delete row.dataset.previewNormal;
    }
  }
  function convRow(c) {
    var kind = String(c.kind || '').toUpperCase();
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
    var mc = c.memberCount ? ' <span class="cnt">(' + c.memberCount + ')</span>' : '';
    var tm = formatTime(c.lastMessageAt);
    var preview = kind === 'AI_ASSISTANT' ? novaConvPreview(c) : esc(c.lastMessagePreview || '');
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
    var roleSpan = kind === 'BROADCAST' ? ' <span class="role">HR · 只读</span>' : '';
    return '<div class="' + rowCls + '" data-go="' + go + '" data-conv-id="' + c.id + '" data-last-at="' + esc(c.lastMessageAt || '') + '">'
      + '<div class="' + avCls + '">' + avInner + '</div>'
      + '<div class="cr-bd"><div class="cr-top"><div class="cr-nm">' + esc(kind === 'AI_ASSISTANT' ? assistantDisplayTitle(c) : (c.title || '会话')) + aiMark + roleSpan + mc + '</div>'
      + '<div class="cr-tm">' + esc(tm) + '</div></div><div class="cr-pv">' + preview + '</div></div>'
      + meta + '</div>';
  }
  function systemRow(n, unread) {
    var pv = n ? esc((n.title || '') + (n.body ? '：' + n.body : '')) : '暂无新通知';
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
      title: 'NOVA',
      lastMessagePreview: preview || NOVA_INTRO,
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
      title: '公司广播 · XYYT',
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
    aiRows += defaultKbChatRow();
    var aiCnt = (ai.length || 1) + 1;
    var pinRows = systemRow(notif, notifUnread);
    pinRows += broadcast.length ? broadcast.map(convRow).join('') : defaultBroadcastRow(placeholders.broadcast);
    var pinCnt = 1 + (broadcast.length || 1);
    var html = '';
    html += section('ti-sparkles', 'NOVA · 24/7 在线', aiCnt, aiRows, true, 'ai', maxConvTs(ai));
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
            patchNovaGeneratingPreview(c.id, !!c.assistantGenerating, c.assistantGeneratingStatus, c.lastMessagePreview);
          }
          list.querySelectorAll('.chat-row[data-conv-id="' + c.id + '"]').forEach(function (row) {
            var n = Number(c.unreadCount || 0);
            var meta = row.querySelector('.cr-meta');
            if (n > 0) {
              if (!meta) {
                meta = document.createElement('div');
                meta.className = 'cr-meta';
                row.appendChild(meta);
              }
              meta.innerHTML = '<span class="badge-num accent">' + n + '</span>';
            } else if (meta) meta.innerHTML = '';
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
      if (!meta && n > 0) {
        meta = document.createElement('div');
        meta.className = 'cr-meta';
        row.appendChild(meta);
      }
      if (!meta) return;
      if (n > 0) meta.innerHTML = '<span class="badge-num accent">' + n + '</span>';
      else meta.innerHTML = '';
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
    var cls = 'noti-card tappable' + (unread ? ' urgent' : '');
    var goAttr = n.clickAction ? ' data-go="' + esc(String(n.clickAction)) + '"' : '';
    var kind = n.kind || '系统';
    var time = n.createdAt ? formatTimeDetailed(n.createdAt, true) : '';
    return '<div class="' + cls + '"' + goAttr + ' data-noti-id="' + (n.id || '') + '">'
      + '<span class="nc-dot"></span><div class="nc-ic"><i class="ti ti-bell"></i></div>'
      + '<div class="nc-body"><div class="nc-top"><div class="nc-title">' + esc(n.title || '')
      + '</div><div class="nc-time">' + esc(time) + '</div></div>'
      + '<div class="nc-desc">' + esc(n.body || '') + '</div>'
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
        var text = notif
          ? esc((notif.title || '') + (notif.body ? '：' + notif.body : ''))
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
  async function loadBroadcastList() {
    var box = document.getElementById('c10-api-rows');
    if (!box) return;
    try {
      await markAllBroadcastsRead();
      var j = await apiFetch('/conversations?kind=BROADCAST');
      if (!j.success) throw new Error(j.message || 'broadcast failed');
      var rows = j.data || [];
      if (!rows.length) {
        box.innerHTML = '<div class="api-strip"><i class="ti ti-info-circle"></i><span>暂无广播</span></div>';
        return;
      }
      box.innerHTML = rows.slice(0, 20).map(function (r) {
        return '<div class="noti-card tappable"><div class="nc-ic"><i class="ti ti-speakerphone"></i></div>'
          + '<div class="nc-body"><div class="nc-top"><div class="nc-title">' + esc(r.title || '公司广播') + '</div></div>'
          + '<div class="nc-desc">' + esc(r.lastMessagePreview || '') + '</div></div></div>';
      }).join('');
    } catch (e) {
      box.innerHTML = '<div class="api-strip"><span>' + esc(String(e.message || e)) + '</span></div>';
      console.warn('loadBroadcastList', e);
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
      if (typeof wireZ2NotiCards === 'function') wireZ2NotiCards();
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
      list.querySelectorAll('.chat-row').forEach(function (row) {
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
      if (n.classList && n.classList.contains('chat-row')) {
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
    var el = row.previousElementSibling;
    var section = null;
    while (el) {
      if (el.classList && el.classList.contains('chat-section')) {
        section = el;
        break;
      }
      el = el.previousElementSibling;
    }
    if (!section || section.nextElementSibling === row) return;
    row.parentNode.insertBefore(row, section.nextElementSibling);
  }
  function applyConvEvent(data) {
    if (!data || !data.conversationId) return;
    var convId = data.conversationId;
    var me = Number(localStorage.getItem('dunes_user_id') || '0');
    var fromPeer = data.message && data.message.sender
      && Number(data.message.sender.userId) !== me;
    var activeScreen = document.querySelector('.screen.active')?.dataset?.screen || '';
    var pendingNova = Number(window.pendingConvId || 0);
    var isNovaAiMsg = data.message && (
      String(data.message.kind || '').indexOf('AI') >= 0
      || (data.message.sender && (!data.message.sender.userId || data.message.sender.displayName === 'NOVA'))
    );
    var viewingNova = activeScreen === 'C4' && pendingNova === Number(convId);
    var bumpUnread = (fromPeer && (data.type === 'message' || data.type === 'system_flow'))
      || (isNovaAiMsg && !viewingNova && data.type === 'message');
    var list = document.getElementById('c1-conv-list');
    if (!list || !list.classList.contains('dunes-api-ready')) {
      if (bumpUnread) scheduleCommBadgeRefresh();
      else scheduleC1Refresh();
      return;
    }
    var row = list.querySelector('.chat-row[data-conv-id="' + convId + '"]');
    if (!row) {
      if (bumpUnread) scheduleCommBadgeRefresh();
      scheduleC1Refresh();
      return;
    }
    var preview = '';
    var at = null;
    if (data.type === 'message' && data.message) {
      preview = data.message.bodyText || '';
      var sysKinds = { SYSTEM: 1, SYSTEM_JOIN: 1, SYSTEM_LEAVE: 1, SYSTEM_REMOVE: 1, SYSTEM_FLOW: 1 };
      if (!sysKinds[data.message.kind] && data.message.sender && data.message.sender.displayName) {
        var go = row.getAttribute('data-go');
        if (go === 'C2' || row.classList.contains('workgroup-approval')) {
          preview = data.message.sender.displayName + ': ' + preview;
        }
      }
      at = data.message.createdAt;
    } else if (data.type === 'message_recalled') {
      preview = (data.preview == null || data.preview === '') ? '消息已撤回' : String(data.preview);
      at = data.previewAt || null;
    } else if (data.type === 'message_updated' && data.message) {
      preview = data.message.bodyText || '';
      at = data.message.createdAt;
    } else if (data.type === 'message_deleted') {
      preview = '消息已删除';
    } else if (data.type === 'system_flow' && data.message) {
      preview = data.message.bodyText || '[系统]';
      at = data.message.createdAt;
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
    if (bumpUnread) scheduleConvUnreadSync(convId);
  }
  async function loadC1() {
    var list = document.getElementById('c1-conv-list');
    var sub = document.querySelector('.screen[data-screen="C1"] .ch-t .sub');
    if (!list) return;
    list.classList.remove('dunes-api-ready');
    list.innerHTML = '';
    try {
      var convJ = await apiFetch('/conversations');
      if (!convJ.success) throw new Error(convJ.message || 'conversations failed');
      var convs = convJ.data || [];
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
      var approval = sortConvList(convs.filter(function (c) { return c.kind === 'WORKGROUP_APPROVAL'; }));
      var groups = sortConvList(convs.filter(function (c) {
        return c.kind === 'WORKGROUP' || c.kind === 'GROUP';
      }));
      var priv = convs.filter(function (c) { return c.kind === 'PRIVATE'; });
      if (sub) sub.textContent = 'CHAT · ' + convs.length;
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
    } catch (e) {
      var errPreview = '消息列表加载失败：' + (e.message || e);
      var fallback = buildFixedSections([], null, 0);
      var errHtml = fallback.html;
      errHtml += section('ti-route', '审批工作群 · 系统自动建群', 0, '', true);
      errHtml += '<div class="api-strip"><span>' + esc(errPreview) + '</span></div>';
      list.innerHTML = errHtml;
      list.classList.add('dunes-api-ready');
      console.warn('DunesInbox.loadC1', e);
    }
  }
  function onScreen(id) {
    if (id === 'C1') {
      ensureC1ScrollWired();
      if (_c1Loaded && window.__dunesRefreshC1OnNextShow) {
        window.__dunesRefreshC1OnNextShow = false;
        loadC1();
      } else if (_c1Loaded) restoreC1Scroll();
      else loadC1();
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
    recalcCommBadgeFromDom: recalcCommBadgeFromDom,
    refreshCommBadgeFromServer: refreshCommBadgeFromServer,
    scheduleCommBadgeRefresh: scheduleCommBadgeRefresh
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
    var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    var headers = Object.assign({}, opts.headers || {});
    if (token) headers.Authorization = 'Bearer ' + token;
    if (opts.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json';
    return fetch(base + path, {
      method: opts.method || 'GET',
      headers: headers,
      body: opts.body || undefined
    }).then(function (r) { return r.json(); });
  }
  function toast(msg) {
    if (window.DunesAPI && window.DunesAPI.toast) window.DunesAPI.toast(msg);
    else alert(msg);
  }
  function dlgConfirm(msg) {
    if (window.DunesDialog && window.DunesDialog.confirm) return window.DunesDialog.confirm(msg);
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
    var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
    return base + '/storage/presigned-get?bucket=' + encodeURIComponent(bucket || 'im-attachments') + '&objectKey=' + encodeURIComponent(objectKey);
  }
  function storageDownloadEndpoint(objectKey, bucket, fileName) {
    if (!objectKey) return '';
    var base = localStorage.getItem('dunes_api_base') || 'http://localhost:6090/api/v1';
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
    var objectKey = payload.objectKey || '';
    var fileName = payload.fileName || item.bodyText || 'download';
    var bucket = payload.bucket || 'im-attachments';
    var token = localStorage.getItem('dunes_token') || localStorage.getItem('dunes_jwt') || '';
    if (objectKey) {
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
    }
    var url = payload.url || payload.previewUrl || '';
    if (!url) throw new Error('无下载地址');
    var r = await fetch(url, { mode: 'cors' });
    if (!r.ok) throw new Error('HTTP ' + r.status);
    var b = await r.blob();
    var u = URL.createObjectURL(b);
    var link = document.createElement('a');
    link.href = u;
    link.download = fileName.replace(/^\[[^\]]+\]\s*/, '');
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(function () { URL.revokeObjectURL(u); }, 2000);
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
    var objectKey = payload.objectKey || '';
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
    var overlay = ensurePickerOverlay();
    overlay.style.display = 'flex';
    document.getElementById('dunes-member-picker-title').textContent =
      pickState.mode === 'remove' ? '选择要移除的成员' : '从通讯录选择成员';
    var searchInp = document.getElementById('dunes-member-picker-search');
    if (searchInp) searchInp.value = '';
    renderPickerList(pickState.candidates, pickState.excludeIds, '');
  }
  async function renderPickerList(candidates, excludeIds, query) {
    var list = document.getElementById('dunes-member-picker-list');
    if (!list) return;
    list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-3)">加载中…</div>';
    var exclude = {};
    (excludeIds || []).forEach(function (id) { exclude[String(id)] = true; });
    var rows = candidates;
    if (!rows) {
      try {
        var q = query ? ('?q=' + encodeURIComponent(query)) : '';
        var j = await apiFetch('/contacts' + q);
        rows = j.success ? (j.data || []) : [];
      } catch (e) { rows = []; }
    }
    rows = (rows || []).filter(function (c) {
      var uid = Number(c.userId);
      if (!uid || uid === devUserId() || exclude[String(uid)]) return false;
      if (!query || candidates) return true;
      var q = String(query).toLowerCase();
      var hay = [c.displayName, c.department, c.departmentName, c.title].join(' ').toLowerCase();
      return hay.indexOf(q) >= 0;
    });
    if (!rows.length) {
      list.innerHTML = '<div style="padding:20px;text-align:center;color:var(--text-3)">暂无可选成员</div>';
      return;
    }
    list.innerHTML = rows.map(function (c) {
      var uid = Number(c.userId);
      return '<div class="contact-pick-row tappable" data-pick-user-id="' + uid + '">'
        + '<div class="cp-check"><i class="ti ti-check"></i></div>'
        + '<div class="cp-av ' + personCls(uid) + '">' + esc((c.displayName || '?').slice(0, 1)) + '</div>'
        + '<div class="cp-bd"><div class="cp-nm">' + esc(c.displayName || '') + '</div>'
        + '<div class="cp-m"><span>' + esc(c.department || c.departmentName || '') + '</span>'
        + '<span>' + esc(c.title || '') + '</span></div></div></div>';
    }).join('');
    list.querySelectorAll('.contact-pick-row').forEach(function (row) {
      row.addEventListener('click', function () {
        var uid = Number(row.getAttribute('data-pick-user-id'));
        if (!pickState) return;
        if (pickState.single) {
          list.querySelectorAll('.contact-pick-row.on').forEach(function (r) { r.classList.remove('on'); });
          pickState.selected.clear();
          pickState.selected.add(uid);
          row.classList.add('on');
        } else {
          if (pickState.selected.has(uid)) {
            pickState.selected.delete(uid);
            row.classList.remove('on');
          } else {
            pickState.selected.add(uid);
            row.classList.add('on');
          }
        }
      });
    });
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
  function wireSettings(detail) {
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
    if (clearBtn && !clearBtn.dataset.wired) {
      clearBtn.dataset.wired = '1';
      clearBtn.addEventListener('click', async function (e) {
        e.preventDefault();
        var convId = currentConvId();
        if (!convId) return;
        if (!(await dlgConfirm('清空后仅对你不可见，确定继续？'))) return;
        try {
          var j = await apiFetch('/conversations/' + convId + '/clear-history', { method: 'POST' });
          if (!j.success) throw new Error(j.message || '清空失败');
          toast('聊天记录已清空');
          if (window.DunesImChat && typeof window.DunesImChat.reloadActiveChat === 'function') {
            window.DunesImChat.reloadActiveChat('C2');
          }
        } catch (err) { toast((err && err.message) || '清空失败'); }
      });
    }
    var leaveBtn = document.getElementById('c6-leave-group');
    if (leaveBtn) {
      var canLeave = !!(detail && detail.canLeave);
      leaveBtn.style.opacity = canLeave ? '1' : '.5';
      leaveBtn.style.cursor = canLeave ? 'pointer' : 'not-allowed';
      if (!leaveBtn.dataset.wired) {
        leaveBtn.dataset.wired = '1';
        leaveBtn.addEventListener('click', async function (e) {
          e.preventDefault();
          var d = window.__dunesGroupDetail || detail;
          if (!d || !d.canLeave) {
            toast('系统群不可退出');
            return;
          }
          var convId = currentConvId();
          if (!convId) return;
          if (!(await dlgConfirm('确定退出该群聊？'))) return;
          try {
            var j = await apiFetch('/conversations/' + convId + '/leave', { method: 'POST' });
            if (!j.success) throw new Error(j.message || '退出失败');
            toast('已退出群聊');
            if (typeof go === 'function') go('C1');
            else if (typeof setScreen === 'function') setScreen('C1', false);
            if (window.DunesInbox && window.DunesInbox.loadC1) window.DunesInbox.loadC1();
          } catch (err) { toast((err && err.message) || '退出失败'); }
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
      if (sub) {
        var bits = [];
        if (d.kind === 'WORKGROUP_APPROVAL') bits.push('审批工作群');
        else if (d.kind === 'WORKGROUP') bits.push('工作群');
        else bits.push(d.kind || '群聊');
        if (d.createdAt) bits.push('创建于 ' + String(d.createdAt).slice(0, 10));
        sub.textContent = bits.join(' · ');
      }
      var members = d.members || [];
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
            + '<div class="gm-nm">' + esc(m.displayName || '') + (me ? '<span style="color:var(--accent);font-size:7px;font-weight:700">' + me + '</span>' : '') + '</div>'
            + '<div class="gm-role">' + esc(m.role || '') + '</div>';
          grid.appendChild(div);
        });
        if (d.isOwner) {
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
    return '<img class="' + cls + '" src="' + src + '" alt="NOVA" draggable="false">';
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
      if (el.textContent.indexOf('NOVA') < 0) return;
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

  __DUNES_DIALOG_JS__
  __DUNES_PROFILE_JS__
  __DUNES_CONTACTS_JS__
  __DUNES_INBOX_JS__
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
      var t = e.target.closest('[data-conv-id],[data-peer-user-id],[data-contact-user-id]');
      if (!t) return;
      var cid = t.dataset.convId ? Number(t.dataset.convId) : 0;
      var pid = Number(t.dataset.peerUserId || t.dataset.contactUserId || 0);
      if (typeof window.__dunesSelectConversation === 'function') {
        window.__dunesSelectConversation(cid, pid);
        return;
      }
      if (t.dataset.contactUserId) window.pendingContactUserId = Number(t.dataset.contactUserId);
      else if (t.dataset.peerUserId) window.pendingContactUserId = Number(t.dataset.peerUserId);
      if (t.dataset.peerUserId) window.__dunesPendingPeerUserId = Number(t.dataset.peerUserId);
      if (cid) {
        window.pendingConvId = cid;
        try { pendingConvId = cid; } catch (e2) {}
      }
    }, true);
  })();

  var origSetScreen = typeof setScreen === 'function' ? setScreen : null;
  if (origSetScreen) {
    setScreen = function (id, back) {
      var prev = document.querySelector('.screen.active')?.dataset?.screen;
      var finish = function () {
        if (prev === 'C4' && id !== 'C4' && window.DunesNovaChat && typeof window.DunesNovaChat.onLeave === 'function') {
          window.DunesNovaChat.onLeave();
        }
        if (prev === 'K2' && id !== 'K2' && window.DunesKbChat && typeof window.DunesKbChat.onLeave === 'function') {
          window.DunesKbChat.onLeave(prev);
        }
        if (prev === 'C12' && id !== 'C12') window.__dunesC12NovaMode = false;
        origSetScreen(id, back);
        if (id === 'B2' && typeof refreshUserProfile === 'function') refreshUserProfile();
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
          if (id === 'B2' && typeof refreshUserProfile === 'function') refreshUserProfile();
          if (id === 'C1' && window.DunesInbox) window.DunesInbox.loadC1();
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

  setTimeout(function () {
    if (typeof refreshUserProfile === 'function') refreshUserProfile();
    if (typeof wireNovaC4 === 'function') wireNovaC4();
    if (typeof window.patchNovaIcons === 'function') window.patchNovaIcons();
    var active = document.querySelector('.screen.active')?.dataset?.screen || 'B2';
    if (window.DunesInbox && typeof window.DunesInbox.refreshCommBadgeFromServer === 'function') {
      window.DunesInbox.refreshCommBadgeFromServer();
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

  static String bootstrapScript() {
    return bootstrapJs
        .replaceAll('__DUNES_CSS__', _escapeJsString(css))
        .replaceAll('__DUNES_DIALOG_JS__', _dialogJs)
        .replaceAll('__DUNES_PROFILE_JS__', _profileJs)
        .replaceAll('__DUNES_CONTACTS_JS__', _contactsJs)
        .replaceAll('__DUNES_INBOX_JS__', _inboxJs)
        .replaceAll('__DUNES_IM_JS__', ImChatInjection.js)
        .replaceAll('__DUNES_KB_CHAT_JS__', KbChatInjection.js)
        .replaceAll('__DUNES_NOVA_JS__', NovaChatInjection.js)
        .replaceAll('__DUNES_GROUP_JS__', _groupInfoJs);
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
      final css =
          await rootBundle.loadString('assets/prototype/tabler-icons.min.css');
      final fontBytes = await rootBundle.load('assets/prototype/tabler-icons.woff2');
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
      _tablerIconsStyleCache = '<style id="dunes-tabler-icons">$inlined</style>';
      return _tablerIconsStyleCache;
    } catch (_) {
      _tablerIconsStyleFailed = true;
      return null;
    }
  }

  static Future<String> preparePrototypeHtml(
    String html, {
    String? token,
    String? apiBase,
    int? userId,
    String? displayName,
    String? phone,
    List<String>? roles,
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
  }) {
    final script =
        '<script>${authScript(token: token, apiBase: apiBase, userId: userId, displayName: displayName, phone: phone, roles: roles)}</script>';
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

  static String authScript({
    String? token,
    String? apiBase,
    int? userId,
    String? displayName,
    String? phone,
    List<String>? roles,
  }) {
    final wsBase = _wsBaseFromApi(apiBase);
    final roleList = roles;
    final entries = <String, String>{};
    if (token != null && token.isNotEmpty) {
      entries['dunes_token'] = token;
      entries['dunes_jwt'] = token;
    }
    if (apiBase != null && apiBase.isNotEmpty) entries['dunes_api_base'] = apiBase;
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
        .map((e) => "localStorage.setItem('${e.key}', ${_escapeJsString(e.value)});")
        .join();
    return 'try{$writes}catch(e){}';
  }

  static String _escapeJsString(String s) {
    return "'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('\n', '\\n').replaceAll('\r', '')}'";
  }

  static String goToScreen(String screenId) =>
      "window.DunesFlutter && window.DunesFlutter.go('$screenId');";

  static String goBack() => "window.DunesFlutter && window.DunesFlutter.back();";

  static String currentScreen() =>
      "window.DunesFlutter ? window.DunesFlutter.currentScreen() : 'B2';";
}
