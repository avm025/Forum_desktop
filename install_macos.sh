#!/usr/bin/env bash
#
# Сборка / установка Forum (forum_app) на macOS.
#
# На своём Mac (подготовка для передачи):
#   ./install_macos.sh --zip          # zip для другого компьютера
#   ./install_macos.sh --dmg          # dmg для другого компьютера
#
# На чужом Mac (после распаковки zip):
#   ./install_on_this_mac.sh
#
set -euo pipefail

APP_NAME="forum_app"
APP_DISPLAY_NAME="Forum"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_APP="${SCRIPT_DIR}/build/macos/Build/Products/Release/${APP_NAME}.app"
DIST_DIR="${SCRIPT_DIR}/dist"
INSTALL_DIR="/Applications"
CREATE_DMG=false
CREATE_ZIP=false
INSTALL_LOCAL=true
OPEN_AFTER=false
SKIP_BUILD=false

log() { printf '→ %s\n' "$*"; }
err() { printf '✗ %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Установка / упаковка Forum для macOS

  ./install_macos.sh [опции]

Опции:
  --zip          Создать dist/${APP_NAME}.zip для передачи на другой Mac
  --dmg          Создать dist/${APP_NAME}.dmg
  --package-only Только упаковать (не ставить в /Applications)
  --open         Запустить после локальной установки
  --skip-build   Не собирать (использовать уже собранный .app)
  --dest PATH    Каталог локальной установки (по умолчанию /Applications)
  --help         Справка

На другом Mac после скачивания zip:
  1. Распаковать архив
  2. В Терминале выполнить:
       xattr -cr ./forum_app.app
       open ./forum_app.app
     или:
       ./install_on_this_mac.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open) OPEN_AFTER=true; shift ;;
    --dmg) CREATE_DMG=true; shift ;;
    --zip) CREATE_ZIP=true; shift ;;
    --package-only) INSTALL_LOCAL=false; CREATE_ZIP=true; shift ;;
    --skip-build) SKIP_BUILD=true; shift ;;
    --dest)
      INSTALL_DIR="${2:?Укажите путь после --dest}"
      shift 2
      ;;
    --help|-h) usage; exit 0 ;;
    *) err "Неизвестная опция: $1 (используйте --help)" ;;
  esac
done

if [[ "$(uname)" != "Darwin" ]]; then
  err "Этот скрипт работает только на macOS"
fi

if ! $SKIP_BUILD; then
  if ! command -v flutter >/dev/null 2>&1; then
    err "Flutter не найден. Установите SDK: https://docs.flutter.dev/get-started/install/macos"
  fi

  if ! xcode-select -p >/dev/null 2>&1; then
    err "Xcode Command Line Tools не установлены. Выполните: xcode-select --install"
  fi

  log "Зависимости Flutter…"
  (cd "$SCRIPT_DIR" && flutter pub get)

  log "Сборка release для macOS…"
  (cd "$SCRIPT_DIR" && flutter build macos --release)
else
  log "Пропуск сборки (--skip-build)"
fi

if [[ ! -d "$BUILD_APP" ]]; then
  err "Не найден ${BUILD_APP}. Запустите без --skip-build."
fi

# Ad-hoc подпись + снятие quarantine перед упаковкой
log "Подготовка .app (codesign + xattr)…"
xattr -cr "$BUILD_APP" 2>/dev/null || true
codesign --force --deep --sign - "$BUILD_APP" 2>/dev/null || true

if $INSTALL_LOCAL; then
  TARGET="${INSTALL_DIR}/${APP_NAME}.app"
  log "Установка в ${TARGET}…"

  if [[ -d "$TARGET" ]]; then
    rm -rf "$TARGET"
  fi

  if [[ "$INSTALL_DIR" == "/Applications" ]] && [[ ! -w "$INSTALL_DIR" ]]; then
    log "Нужны права администратора для /Applications"
    sudo mkdir -p "$INSTALL_DIR"
    sudo ditto "$BUILD_APP" "$TARGET"
    sudo xattr -cr "$TARGET" 2>/dev/null || true
  else
    mkdir -p "$INSTALL_DIR"
    ditto "$BUILD_APP" "$TARGET"
    xattr -cr "$TARGET" 2>/dev/null || true
  fi
  log "Готово: ${TARGET}"
fi

mkdir -p "$DIST_DIR"

write_install_helper() {
  local dir="$1"
  cat > "${dir}/install_on_this_mac.sh" <<'HELPER'
#!/usr/bin/env bash
# Запуск на Mac, куда передали forum_app.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${SCRIPT_DIR}/forum_app.app"
TARGET="/Applications/forum_app.app"

if [[ ! -d "$APP" ]]; then
  echo "Не найден forum_app.app рядом со скриптом."
  exit 1
fi

echo "→ Снятие блокировки Gatekeeper (quarantine)…"
xattr -cr "$APP" 2>/dev/null || true

echo "→ Копирование в Программы…"
if [[ ! -w /Applications ]]; then
  sudo ditto "$APP" "$TARGET"
  sudo xattr -cr "$TARGET" 2>/dev/null || true
else
  ditto "$APP" "$TARGET"
  xattr -cr "$TARGET" 2>/dev/null || true
fi

echo "→ Запуск…"
open "$TARGET"
echo "Готово. Если снова блокирует: ПКМ по forum_app → Открыть → Открыть"
HELPER
  chmod +x "${dir}/install_on_this_mac.sh"

  cat > "${dir}/КАК_УСТАНОВИТЬ.txt" <<'TXT'
Установка Forum на этот Mac
===========================

Способ 1 (проще):
  1. Дважды щёлкните install_on_this_mac.sh
     (или в Терминале: ./install_on_this_mac.sh)
  2. При запросе пароля — введите пароль Mac

Способ 2 (вручную):
  1. Откройте Терминал в этой папке
  2. Выполните:
       xattr -cr ./forum_app.app
  3. Перетащите forum_app.app в папку «Программы»
  4. ПКМ по приложению → «Открыть» → «Открыть»

Почему блокирует macOS?
  Приложение собрано без аккаунта Apple Developer (ad-hoc подпись).
  Gatekeeper считает такие файлы «из интернета» небезопасными,
  пока вы явно не разрешите запуск.

Требования: macOS 12 или новее (Intel и Apple Silicon).
TXT
}

if $CREATE_ZIP; then
  ZIP_PATH="${DIST_DIR}/${APP_NAME}.zip"
  STAGING="${DIST_DIR}/zip-staging"
  log "Создание ZIP для передачи…"
  rm -rf "$STAGING" "$ZIP_PATH"
  mkdir -p "$STAGING"
  ditto "$BUILD_APP" "${STAGING}/${APP_NAME}.app"
  xattr -cr "${STAGING}/${APP_NAME}.app" 2>/dev/null || true
  write_install_helper "$STAGING"
  # ditto -c -k сохраняет атрибуты .app лучше, чем zip
  ditto -c -k --sequesterRsrc --keepParent "$STAGING" "$ZIP_PATH"
  rm -rf "$STAGING"
  log "ZIP: ${ZIP_PATH}"
  log "Передайте этот файл на другой Mac (AirDrop / USB / облако)."
fi

if $CREATE_DMG; then
  DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
  STAGING="${DIST_DIR}/dmg-staging"
  log "Создание DMG…"
  rm -rf "$STAGING" "$DMG_PATH"
  mkdir -p "$STAGING"
  ditto "$BUILD_APP" "${STAGING}/${APP_NAME}.app"
  xattr -cr "${STAGING}/${APP_NAME}.app" 2>/dev/null || true
  write_install_helper "$STAGING"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create \
    -volname "$APP_DISPLAY_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null
  rm -rf "$STAGING"
  log "DMG: ${DMG_PATH}"
fi

if $OPEN_AFTER && $INSTALL_LOCAL; then
  log "Запуск…"
  open "${INSTALL_DIR}/${APP_NAME}.app"
fi
