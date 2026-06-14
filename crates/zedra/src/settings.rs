use std::path::PathBuf;

use gpui::{App, Context, Entity, EventEmitter, Global, WeakEntity};
use serde::{Deserialize, Serialize};
use tracing::{debug, warn};

use crate::theme::{ThemeBundle, ThemePreference};

const STORE_DIR: &str = "zedra";
const SETTINGS_FILE: &str = "settings.json";

#[derive(Clone, Debug, Default, Serialize, Deserialize)]
struct AppSettings {
    /// Set when the user picks a theme in Settings; `None` follows the system on next launch.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    theme_preference: Option<ThemePreference>,
    /// Claude launch/resume profile, replacing the bare `claude` binary.
    /// `None` means "use the default profile".
    #[serde(default, skip_serializing_if = "Option::is_none")]
    claude_command: Option<String>,
    /// Deprecated legacy resume template. Read-only migration source; cleared
    /// on the next write so the key disappears from disk.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    claude_resume_command: Option<String>,
}

pub enum ThemeStateEvent {
    Changed,
}

impl EventEmitter<ThemeStateEvent> for ThemeState {}

pub struct ThemeState {
    preference: ThemePreference,
    bundle: ThemeBundle,
}

impl ThemeState {
    pub fn new(_cx: &mut Context<Self>) -> Self {
        let preference = Self::load_preference();
        let bundle = ThemeBundle::for_preference(preference);
        Self::sync_native_theme(preference);
        Self { preference, bundle }
    }

    pub fn preference(&self) -> ThemePreference {
        self.preference
    }

    pub fn bundle(&self) -> &ThemeBundle {
        &self.bundle
    }

    pub fn palette(&self) -> &crate::theme::ThemePalette {
        &self.bundle.ui
    }

    pub fn set_preference(&mut self, preference: ThemePreference, cx: &mut Context<Self>) {
        if self.preference == preference {
            return;
        }
        self.preference = preference;
        self.bundle = ThemeBundle::for_preference(preference);
        Self::sync_native_theme(preference);
        Self::save_preference(preference);
        cx.emit(ThemeStateEvent::Changed);
        cx.notify();
    }

    pub fn register_global(entity: WeakEntity<Self>, cx: &mut App) {
        cx.set_global(ThemeStateHandle(entity));
    }

    fn load_preference() -> ThemePreference {
        match read_settings() {
            Ok(settings) => settings.theme_preference.unwrap_or_default(),
            Err(err) => {
                debug!(err = %err, "settings: using default theme preference");
                ThemePreference::default()
            }
        }
    }

    pub(crate) fn preference_from_system() -> ThemePreference {
        match crate::platform_bridge::bridge().system_prefers_theme() {
            crate::platform_bridge::SystemTheme::Dark => ThemePreference::Dark,
            crate::platform_bridge::SystemTheme::Light => ThemePreference::Light,
            crate::platform_bridge::SystemTheme::Unknown => ThemePreference::default(),
        }
    }

    fn save_preference(preference: ThemePreference) {
        let mut settings = read_settings().unwrap_or_default();
        settings.theme_preference = Some(preference);
        if let Err(err) = write_settings(&settings) {
            warn!(err = %err, "settings: failed to save theme preference");
        }
    }

    fn sync_native_theme(preference: ThemePreference) {
        crate::platform_bridge::bridge().set_native_theme(preference == ThemePreference::Dark);
    }
}

#[derive(Clone)]
pub struct ThemeStateHandle(WeakEntity<ThemeState>);

impl Global for ThemeStateHandle {}

pub fn theme_state(cx: &App) -> Option<Entity<ThemeState>> {
    cx.try_global::<ThemeStateHandle>()
        .and_then(|handle| handle.0.upgrade())
}

pub fn palette(cx: &App) -> crate::theme::ThemePalette {
    theme_state(cx)
        .map(|theme| theme.read(cx).palette().clone())
        .unwrap_or_else(|| ThemeBundle::dark().ui)
}

pub fn bundle(cx: &App) -> ThemeBundle {
    theme_state(cx)
        .map(|theme| theme.read(cx).bundle().clone())
        .unwrap_or_else(ThemeBundle::dark)
}

fn data_directory() -> Option<PathBuf> {
    crate::platform_bridge::bridge()
        .data_directory()
        .map(PathBuf::from)
}

fn settings_path() -> Option<PathBuf> {
    let dir = data_directory()?.join(STORE_DIR);
    if !dir.exists() {
        std::fs::create_dir_all(&dir).ok()?;
    }
    Some(dir.join(SETTINGS_FILE))
}

fn read_settings() -> Result<AppSettings, String> {
    let path = settings_path().ok_or_else(|| "settings path unavailable".to_string())?;
    if !path.exists() {
        return Ok(AppSettings::default());
    }
    let contents = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    serde_json::from_str(&contents).map_err(|e| e.to_string())
}

fn write_settings(settings: &AppSettings) -> Result<(), String> {
    let path = settings_path().ok_or_else(|| "settings path unavailable".to_string())?;
    let contents = serde_json::to_string_pretty(settings).map_err(|e| e.to_string())?;
    std::fs::write(path, contents).map_err(|e| e.to_string())
}

// ---------------------------------------------------------------------------
// Claude command profile (launch + resume)
// ---------------------------------------------------------------------------

/// Default Claude profile when unset or cleared.
pub const DEFAULT_CLAUDE_COMMAND: &str = "ccs glm-lite --dangerously-skip-permissions";

/// Internal client/host token the host replaces with the shell-quoted session
/// id. Never appears in the user-facing profile field.
pub const RESUME_SESSION_ID_TOKEN: &str = "{session_id}";
const RESUME_QUOTED_TOKEN: &str = "{quoted}";

/// Resolve the effective Claude profile: the stored value, the migrated legacy
/// resume template (one-time), or the default. Never returns empty.
pub fn claude_command() -> String {
    let mut settings = match read_settings() {
        Ok(settings) => settings,
        Err(_) => return DEFAULT_CLAUDE_COMMAND.to_string(),
    };

    if let Some(cmd) = settings.claude_command.take() {
        let trimmed = cmd.trim().to_string();
        return if trimmed.is_empty() {
            DEFAULT_CLAUDE_COMMAND.to_string()
        } else {
            trimmed
        };
    }

    // One-time migration: strip tokens and orphaned `--resume` from the legacy
    // resume template, persist as `claude_command`, drop the legacy key.
    if let Some(legacy) = settings.claude_resume_command.take() {
        let migrated = profile_from_legacy_resume_template(&legacy);
        settings.claude_command = Some(migrated.clone());
        settings.claude_resume_command = None;
        if let Err(err) = write_settings(&settings) {
            warn!(err = %err, "settings: failed to persist migrated claude command");
        }
        return migrated;
    }

    DEFAULT_CLAUDE_COMMAND.to_string()
}

/// Persist the Claude profile. An empty/whitespace value resets to the default
/// (stored as `None`). Returns the effective value for the caller to cache.
pub fn set_claude_command(value: &str) -> String {
    let resolved = match value.trim() {
        "" => None,
        trimmed => Some(trimmed.to_string()),
    };
    let mut settings = read_settings().unwrap_or_default();
    settings.claude_command = resolved.clone();
    settings.claude_resume_command = None; // clear legacy key if present
    if let Err(err) = write_settings(&settings) {
        warn!(err = %err, "settings: failed to save claude command");
    }
    resolved.unwrap_or_else(|| DEFAULT_CLAUDE_COMMAND.to_string())
}

/// Recover the launch-profile base from a legacy resume template by removing the
/// session-id tokens and any orphaned `--resume` flag.
fn profile_from_legacy_resume_template(template: &str) -> String {
    let cleaned = template
        .replace(RESUME_SESSION_ID_TOKEN, "")
        .replace(RESUME_QUOTED_TOKEN, "");
    cleaned
        .split_whitespace()
        .filter(|token| *token != "--resume")
        .collect::<Vec<_>>()
        .join(" ")
}

#[cfg(test)]
mod tests {
    use super::ThemeState;
    use crate::theme::{ThemeBundle, ThemePalette, ThemePreference};

    #[test]
    fn default_preference_is_dark() {
        assert_eq!(ThemePreference::default(), ThemePreference::Dark);
    }

    #[test]
    fn preference_from_system_falls_back_to_dark_when_unknown() {
        // StubBridge returns Unknown for system_prefers_theme.
        assert_eq!(ThemeState::preference_from_system(), ThemePreference::Dark);
    }

    #[test]
    fn bundle_matches_preference() {
        assert_eq!(
            ThemeBundle::for_preference(ThemePreference::Light)
                .ui
                .bg_primary,
            ThemePalette::light().bg_primary
        );
    }
}

#[cfg(test)]
mod claude_command_tests {
    use super::{DEFAULT_CLAUDE_COMMAND, profile_from_legacy_resume_template};

    #[test]
    fn default_is_ccs_profile() {
        assert_eq!(
            DEFAULT_CLAUDE_COMMAND,
            "ccs glm-lite --dangerously-skip-permissions"
        );
    }

    #[test]
    fn migration_strips_session_id_token_and_resume_flag() {
        assert_eq!(
            profile_from_legacy_resume_template("ccs glm-pro --resume {session_id}"),
            "ccs glm-pro"
        );
        assert_eq!(
            profile_from_legacy_resume_template(
                "ccs glm-pro-personal --dangerously-skip-permissions --resume {quoted}"
            ),
            "ccs glm-pro-personal --dangerously-skip-permissions"
        );
    }

    #[test]
    fn migration_keeps_profile_without_token_unchanged() {
        assert_eq!(
            profile_from_legacy_resume_template("ccs glm-pro --dangerously-skip-permissions"),
            "ccs glm-pro --dangerously-skip-permissions"
        );
    }
}
