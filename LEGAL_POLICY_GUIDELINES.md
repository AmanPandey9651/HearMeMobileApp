# Legal & Policy Governance Guide (Privacy Policy, Terms of Service & Refund Policy)

This guide documents the authoritative structure and upload methodology for managing **Privacy Policy**, **Terms of Service**, and **Refund & Cancellation Policy** across FeelBack / TalkStrangers **Web App**, **Admin Dashboard**, and **Flutter Mobile App**.

---

## 1. How It Works Across All Platforms

```
┌─────────────────────────────────────────────────────────────────┐
│                    Admin Dashboard                              │
│       (Governance & Safety > Legal Policies CMS)               │
└───────────────────────────────┬─────────────────────────────────┘
                                │
               PUT /api/v1/admin/legal-policies/{type}
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│              Backend Service & Multi-Tier Storage               │
│   • In-Memory Cache (Atomic, 0ms latency)                      │
│   • PostgreSQL Database (platform.legal_policies table)         │
│   • JSON File Snapshot Fallback (uploads/legal-policies.json)   │
└───────────────────────┬─────────────────┬───────────────────────┘
                        │                 │
     GET /api/v1/config/legal-policies    GET /api/v1/config/legal-policies
                        │                 │
                        ▼                 ▼
             ┌──────────────────┐ ┌──────────────────┐
             │     Web App      │ │    Mobile App    │
             │   (React/Vite)   │ │    (Flutter)     │
             └──────────────────┘ └──────────────────┘
```

1. **Admin Panel**: Accessible at `/hearme/admin?tab=legal` under the **Governance & Safety** sidebar menu.
2. **Backend**: Spring Boot endpoints provide public discovery and admin-only updates with multi-tier persistence (PostgreSQL + JSON snapshot).
3. **Web App**: Live at `/privacy-policy`, `/terms-of-service`, and `/refund-policy` with dark glassmorphic cards, Lucide icons, and responsive layouts.
4. **Mobile App**: Native Flutter `LegalPolicyScreen` with 3 tabs, pill badges, and material cards.

---

## 2. Preventing UI Hampering (Golden Rules)

To ensure the design, responsiveness, and layout are **never compromised** on either Web or Mobile:

### Rule 1: Use Atomic Sections (Clauses)
- Do **not** paste giant walls of unformatted text or raw HTML into a single box.
- Create a distinct section for each clause (e.g. *1. Strict Zero Call Recording Architecture*, *2. 100% Zero-PII Caller Isolation*).
- Number each title sequentially (e.g. `1. ...`, `2. ...`).

### Rule 2: Formatting Clause Text
- **Paragraphs**: Separate paragraphs with a **double Enter** (a blank line).
- **Bullet Points**: Start each bullet point on a new line with `• ` (bullet symbol) or `- ` (dash followed by space).
- **SLA Commitments**: Prefix with `✓ SLA Guarantee:` for highlight styling.
- **Critical Warnings / Disclaimers**: Prefix with `⚠️ IMPORTANT:` for red/amber caution styling.

### Rule 3: Choose Visual Accents
- **Icons**: Select from standard presets: `shield`, `lock`, `eye-off`, `mic-off`, `scale`, `alert`, `clock`, `refresh`, `dollar`, `trash`, `heart`.
- **Colors**: Use the color picker or palette presets:
  - Green (`#10b981`): Compliance, guarantees, refund approvals.
  - Pink/Purple (`#ec4899`, `#8b5cf6`): Privacy, caller identity isolation.
  - Blue/Cyan (`#3b82f6`, `#38bdf8`): SLAs, time limits, technical security.
  - Amber/Red (`#f59e0b`, `#ef4444`): Medical disclaimers, prohibited conduct.

### Rule 4: Always Maintain Grievance Redressal Officer Info
Under Indian IT Act 2021 Intermediary Guidelines and DPDP Act 2023, platforms must publish:
- Officer Name
- Email address (e.g. `feelback.help@gmail.com`)
- Physical address
- Turnaround SLA (e.g. *Within 48 hours for data deletion requests*)

---

## 3. Authoritative JSON Structure

You can export, edit in your preferred editor, and import JSON directly via the **Import / Export JSON** button in the Admin Dashboard:

```json
{
  "policyType": "PRIVACY_POLICY",
  "title": "Privacy Policy & Data Protection Declaration",
  "badge": "DPDP Act 2023 Compliant",
  "badgeColor": "#10B981",
  "subtitle": "Last updated: October 18, 2026 • FeelBack Technologies Inc.",
  "heroSummary": "At FeelBack, privacy is not an afterthought—it is the fundamental architecture of our platform. We strictly isolate caller identity, never record your voice or video calls, and adhere strictly to India's Digital Personal Data Protection Act (DPDP Act 2023) and global app store privacy standards.",
  "lastUpdatedDate": "October 18, 2026",
  "badges": [
    { "label": "DPDP Act 2023 Compliant", "variant": "success" },
    { "label": "100% Zero-PII Caller Isolation", "variant": "pink" },
    { "label": "Zero Call Recording", "variant": "purple" }
  ],
  "sections": [
    {
      "id": "zero-recording",
      "number": "1",
      "title": "1. Strict Zero Call Recording Architecture",
      "icon": "mic-off",
      "iconColor": "#ef4444",
      "content": "All voice and video sessions utilize transient peer-to-peer WebRTC connections secured with DTLS/SRTP encryption. Media streams flow directly in-flight between participants.\n\nFeelBack does NOT record, listen to, tap, analyze, transcribe, or store audio/video conversations on any server. Once your session ends, the transient media stream disappears permanently."
    },
    {
      "id": "caller-isolation",
      "number": "2",
      "title": "2. 100% Zero-PII Caller Isolation",
      "icon": "eye-off",
      "iconColor": "#f95b3d",
      "content": "Your privacy is protected by design:\n• Listeners never see your phone number, real name, email, or physical location.\n• You interact solely under a chosen pseudonym or nickname.\n• No GSM/PSTN telephony bridging is used, eliminating any risk of caller-ID exposure."
    },
    {
      "id": "account-deletion",
      "number": "3",
      "title": "3. Account & Data Deletion (Play Store SLA)",
      "icon": "trash",
      "iconColor": "#8b5cf6",
      "content": "In compliance with Google Play Store & Apple App Store user data policies, you have the absolute right to delete your account.\n\nTo purge all your data:\n1. Email feelback.help@gmail.com with subject \"Request Account Deletion\" stating your phone or email, OR\n2. Submit a request inside Safety & Support screen.\n\n✓ SLA Guarantee: Your account credentials, auth tokens, and profile will be permanently erased from our primary database within 48 hours."
    }
  ],
  "grievance": {
    "title": "Data Protection & Grievance Officer",
    "officerName": "Aman Pandey",
    "email": "feelback.help@gmail.com",
    "address": "FeelBack Technologies, Prayagraj, Uttar Pradesh, India - 211019",
    "responseSla": "Within 48 hours for account deletion, within 7 business days for grievance resolution."
  }
}
```

---

## 4. API Endpoints Reference

| Method | Endpoint | Access | Purpose |
|---|---|---|---|
| `GET` | `/api/v1/config/legal-policies` | **Public** | Returns all 3 policies for Web & Mobile clients |
| `GET` | `/api/v1/config/legal-policies/{type}` | **Public** | Returns a single policy (`PRIVACY_POLICY`, `TERMS_OF_SERVICE`, `REFUND_CANCELLATION`) |
| `GET` | `/api/v1/admin/legal-policies` | **Admin Only** | Fetch all policies for the CMS editor |
| `PUT` | `/api/v1/admin/legal-policies/{type}` | **Admin Only** | Update and publish a specific policy |
| `PUT` | `/api/v1/admin/legal-policies` | **Admin Only** | Bulk update all policies |
| `POST` | `/api/v1/admin/legal-policies/reset/{type}` | **Admin Only** | Reset policy to verified platform default |

---

## 5. Summary of Admin Features

1. **Tab Switcher**: Toggle between Privacy Policy, Terms of Service, and Refund & Cancellation Policy.
2. **Interactive Clause Editor**:
   - Add new clauses with `+ Add New Clause`.
   - Reorder clauses up or down.
   - Delete unwanted clauses.
   - Live character count and formatting tips.
3. **Live Client Preview**: Toggle between Web View and Native Mobile Preview to inspect how your changes appear on real devices before publishing.
4. **One-Click Default Reset**: If mistakes are made, the "Reset Default" button immediately restores legally compliant company defaults.
5. **JSON Import/Export**: Copy-paste JSON or export backup files at any time.