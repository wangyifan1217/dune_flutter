mod acp;
mod commands;
mod git;
mod memory;
mod models;
mod persist;
mod process_win;
mod state;
mod terminal;
mod workspace;

pub use process_win::run_hidden_child;

use std::sync::Arc;

use tauri::{
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, WindowEvent,
};
use tracing_subscriber::EnvFilter;

use crate::state::AppState;
use crate::terminal::TerminalState;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_clipboard_manager::init())
        .setup(|app| {
            let loaded = commands::get_settings(app.handle().clone()).unwrap_or_default();
            app.manage(Arc::new(AppState::new(loaded)));
            app.manage(Arc::new(TerminalState::new()));

            let show_i = MenuItem::with_id(app, "show", "显示窗口", true, None::<&str>)?;
            let quit_i = MenuItem::with_id(app, "quit", "退出", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show_i, &quit_i])?;

            let _tray = TrayIconBuilder::with_id("main-tray")
                .tooltip("Nova Build 桌面版")
                .icon(
                    app.default_window_icon()
                        .expect("missing default window icon")
                        .clone(),
                )
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(window) = app.get_webview_window("main") {
                            let _ = window.show();
                            let _ = window.unminimize();
                            let _ = window.set_focus();
                        }
                    }
                    "quit" => {
                        app.exit(0);
                    }
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.unminimize();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            Ok(())
        })
        .on_window_event(|window, event| {
            if let WindowEvent::CloseRequested { api, .. } = event {
                // 点关闭 → 隐藏到托盘，不退出
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_settings,
            commands::save_settings,
            commands::update_runtime_settings,
            commands::get_agent_status,
            commands::connect_default_agent,
            commands::clear_workspace,
            commands::read_dropped_files,
            commands::open_generated_file,
            commands::set_workspace,
            commands::disconnect_agent,
            commands::reconnect_agent,
            commands::send_prompt,
            commands::cancel_prompt,
            commands::open_url,
            commands::list_workspace,
            commands::get_workspace_tree,
            commands::read_workspace_file,
            commands::list_memories,
            commands::add_memory,
            commands::delete_memory,
            commands::clear_memories,
            commands::load_sessions,
            commands::save_sessions,
            commands::respond_permission,
            commands::git_list_changes,
            commands::git_file_diff,
            commands::git_accept_change,
            commands::git_reject_change,
            commands::git_reject_all,
            commands::terminal_start,
            commands::terminal_write,
            commands::terminal_resize,
            commands::terminal_stop,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
