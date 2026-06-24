// Firebase Cloud Functions entry point.
// 各ドメインモジュールを require して再 export するだけのバレル。
// 実装は functions/src/{notifications,calendar,accounts,ai,hug,monitoring,intake}/ 配下を参照。

// utils/setup を最初に require して initializeApp() を一度だけ実行させる。
require('./src/utils/setup');

module.exports = {
  ...require('./src/notifications'),
  ...require('./src/calendar'),
  ...require('./src/accounts'),
  ...require('./src/ai'),
  ...require('./src/hug/sync'),
  ...require('./src/hug/docs'),
  ...require('./src/hug/recipient_sync'),
  ...require('./src/hug/inspect_forms'),
  ...require('./src/hug/family_register'),
  ...require('./src/monitoring'),
  ...require('./src/intake/form_intake'),
  ...require('./src/intake/intake_final'),
  ...require('./src/morning_meeting'),
};
