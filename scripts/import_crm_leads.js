/**
 * NotionエクスポートCSV → Firestore crm_leads へインポート
 *
 * 実行: cd functions && node ../scripts/import_crm_leads.js
 */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { parse } = require("csv-parse/sync");

const serviceAccount = require("./service-account.json");
admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

const CSV_PATH =
  "/Users/uedayousuke/Downloads/プライベート、シェア 2/BSP湘南藤沢教室_CRM/無題 c2d9653ec8284ba5b64ba9f5779ae9b6_all.csv";

// ---------- ヘルパ ----------
function parseJpDate(s) {
  if (!s) return null;
  // "2024年6月15日"
  const m = s.match(/(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日/);
  if (m) return new Date(+m[1], +m[2] - 1, +m[3]);
  return null;
}

function splitName(full) {
  if (!full) return { last: "", first: "" };
  const cleaned = full.replace(/\s+/g, " ").trim();
  const parts = cleaned.split(" ");
  if (parts.length >= 2) return { last: parts[0], first: parts.slice(1).join("") };
  // 空白で切れない場合は全部 last に入れる
  return { last: cleaned, first: "" };
}

function mapStage(s) {
  const v = (s || "").trim();
  if (v === "辞退") return "lost";
  if (v === "入会") return "won";
  if (v === "検討中") return "considering";
  if (v === "入会準備中") return "onboarding";
  return "new";
}

function mapGender(s) {
  const v = (s || "").trim();
  if (v === "男") return "男";
  if (v === "女") return "女";
  return "";
}

function mapSource(s) {
  const v = (s || "").trim();
  // Notion側はほぼ "ビースマイリー" のみ。明確な区別がないため other で入れる。
  if (!v) return "other";
  if (v.includes("Instagram") || v.includes("インスタ")) return "instagram";
  if (v.includes("紹介")) return "referral_other";
  if (v.includes("チラシ")) return "flyer";
  if (v.includes("HP") || v.includes("Web") || v.includes("検索")) return "website";
  return "other";
}

function ts(d) {
  return d ? admin.firestore.Timestamp.fromDate(d) : null;
}

// ---------- メイン ----------
async function main() {
  const raw = fs.readFileSync(CSV_PATH, "utf8");
  const rows = parse(raw, { columns: true, skip_empty_lines: true, relax_quotes: true });
  console.log(`Parsed ${rows.length} rows`);

  // 既存インポート済みを削除（再実行対応）
  const existing = await db
    .collection("crm_leads")
    .where("importSource", "==", "notion_initial")
    .get();
  if (!existing.empty) {
    console.log(`Deleting ${existing.size} existing imported docs...`);
    const batch = db.batch();
    existing.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }

  let ok = 0;
  let skipped = 0;
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const r of rows) {
    const parentFull = (r["名前"] || "").trim();
    const childFirst = (r["お子さまの名前"] || "").trim();
    const inquired = parseJpDate(r["問い合わせ日"]);
    // 空行スキップ
    if (!parentFull && !childFirst && !inquired) {
      skipped++;
      continue;
    }
    const { last: pLast, first: pFirst } = splitName(parentFull);
    const stage = mapStage(r["ステータス"]);
    const trialAt = parseJpDate(r["体験日"]);
    const nextAt = parseJpDate(r["対応期日"]);
    const birth = parseJpDate(r["誕生日"]);
    const source = mapSource(r["応募経路"]);
    const lossDetail = (r["辞退理由"] || "").trim();
    const enrolled = stage === "won" ? trialAt || inquired : null;

    const data = {
      importSource: "notion_initial",
      childLastName: "",
      childFirstName: childFirst,
      childKana: (r["ふりがな"] || "").trim(),
      childGender: mapGender(r["性別"]),
      childBirthDate: ts(birth),
      kindergarten: (r["保育園/幼稚園"] || "").trim(),
      permitStatus: "none",
      parentLastName: pLast,
      parentFirstName: pFirst,
      parentKana: "",
      parentTel: (r[" TEL"] || r["TEL"] || "").trim(),
      parentEmail: (r["メール"] || "").replace(/^mailto:/, "").trim(),
      parentLine: "",
      preferredChannel: "tel",
      address: [(r["お住いの地域"] || "").trim(), (r["住所"] || "").trim()]
        .filter(Boolean)
        .join(" "),
      stage,
      confidence: stage === "won" ? "A" : stage === "lost" ? "C" : "B",
      source,
      sourceDetail: (r["応募経路"] || "").trim(),
      preferredDays: "",
      preferredTimeSlots: "",
      preferredStart: "",
      mainConcern: (r["主訴"] || "").trim(),
      likes: (r["好きなこと"] || "").trim(),
      dislikes: (r["苦手なこと"] || "").trim(),
      trialNotes: (r["体験で分かったこと/聞いたこと"] || "").trim(),
      nextActionAt: ts(nextAt),
      nextActionNote: (r["現状・ネクストアクション"] || "").trim(),
      inquiredAt: ts(inquired) || now,
      firstContactedAt: null,
      trialAt: ts(trialAt),
      enrolledAt: ts(enrolled),
      lostAt: stage === "lost" ? ts(inquired) : null,
      lossReason: stage === "lost" ? "other" : null,
      lossDetail: stage === "lost" ? lossDetail : "",
      reapproachOk: true,
      memo: (r["備考"] || "").trim(),
      activities: [],
      createdAt: now,
      updatedAt: now,
      createdBy: "import:notion",
    };

    await db.collection("crm_leads").add(data);
    ok++;
    if (ok % 10 === 0) console.log(`  imported ${ok}...`);
  }

  console.log(`\n✅ Imported: ${ok}, Skipped: ${skipped}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
