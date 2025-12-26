# Mail.app Newsletter Import Setup

This guide explains how to automatically import newsletter emails from Mail.app into DataPointsAI.

## Overview

The integration works by:
1. Creating a Mail.app rule that matches your newsletter emails
2. Running an AppleScript that exports matching emails to a watch folder
3. DataPointsAI monitors the watch folder and automatically imports new `.eml` files

## Prerequisites

- macOS with Mail.app configured
- DataPointsAI app installed and running
- Newsletter watch folder configured in DataPointsAI settings

## Step 1: Configure DataPointsAI Watch Folder

1. Open DataPointsAI
2. Go to **Settings** (gear icon or Cmd+,)
3. Select the **Newsletters** tab
4. Click **Choose Folder** to select or create a watch folder
   - Suggested: `~/Documents/DataPointsAI Newsletters/`
5. Enable **Auto-import new emails** toggle
6. Optionally enable:
   - **Auto-summarize** - automatically generate summaries for imported newsletters
   - **Delete after import** - remove `.eml` files after successful import

## Step 2: Install the AppleScript

### Option A: Save as Script (Recommended)

1. Open **Script Editor** (Applications > Utilities > Script Editor)
2. Open the script file: `scripts/ExportNewsletterToDataPointsAI.applescript`
   - Or copy from `~/Documents/ExportNewsletterToDataPointsAI.applescript`
3. Edit the `destinationFolder` property to match your watch folder:
   ```applescript
   property destinationFolder : "~/Documents/DataPointsAI Newsletters/"
   ```
4. Save as:
   - **File > Save**
   - Format: **Script** (.scpt)
   - Location: `~/Library/Application Scripts/com.apple.mail/`
   - Name: `ExportNewsletterToDataPointsAI.scpt`

### Option B: Save as Application

1. Follow steps 1-3 above
2. Save as:
   - **File > Export**
   - Format: **Application**
   - Location: Applications folder or another convenient location
   - Name: `ExportNewsletterToDataPointsAI.app`

## Step 3: Create Mail.app Rule

1. Open **Mail.app**
2. Go to **Mail > Settings** (or Cmd+,)
3. Click the **Rules** tab
4. Click **Add Rule**
5. Configure the rule:

### Example Rule: Import All Newsletters

```
Description: Export to DataPointsAI
If ANY of the following conditions are met:
  - From contains "substack.com"
  - From contains "newsletter"
  - From contains "digest"
  - [Add your newsletter senders]
Perform the following actions:
  - Run AppleScript: ExportNewsletterToDataPointsAI
```

### Example Rule: Specific Newsletter

```
Description: Export Morning Brew
If ALL of the following conditions are met:
  - From contains "morningbrew.com"
Perform the following actions:
  - Run AppleScript: ExportNewsletterToDataPointsAI
```

### Example Rule: By Subject Pattern

```
Description: Export Weekly Digests
If ANY of the following conditions are met:
  - Subject contains "Weekly Digest"
  - Subject contains "Weekly Roundup"
  - Subject contains "This Week"
Perform the following actions:
  - Run AppleScript: ExportNewsletterToDataPointsAI
```

### Example Rule: By Header (List-Unsubscribe)

Most newsletters include a `List-Unsubscribe` header. You can match on this:

```
Description: Export All Newsletters
If ALL of the following conditions are met:
  - Any Header contains "List-Unsubscribe"
Perform the following actions:
  - Run AppleScript: ExportNewsletterToDataPointsAI
```

6. Click **OK** to save the rule
7. When prompted, choose whether to apply the rule to existing messages

## Step 4: Test the Integration

### Test the AppleScript Manually

1. Open Mail.app
2. Select one or more newsletter emails
3. Open Script Editor
4. Open `ExportNewsletterToDataPointsAI.scpt`
5. Click **Run** (play button)
6. Check the watch folder for exported `.eml` files
7. Check DataPointsAI Library for imported newsletters

### Test the Mail Rule

1. Send yourself a test email matching your rule conditions
2. Or move an existing email out of and back into the inbox
3. Check the watch folder and DataPointsAI

## Troubleshooting

### Script Not Running

- Ensure the script is in `~/Library/Application Scripts/com.apple.mail/`
- Check that Mail.app has permission to run scripts:
  - System Settings > Privacy & Security > Automation
  - Ensure Mail.app can control Script Editor or itself

### Permission Denied Errors

- Grant Full Disk Access to Mail.app:
  - System Settings > Privacy & Security > Full Disk Access
  - Add Mail.app

### Emails Not Exporting

- Verify the watch folder path in the script matches your settings
- Check that the folder exists and is writable
- Look for errors in Script Editor's log when running manually

### Emails Not Importing

- Ensure DataPointsAI is running
- Verify "Auto-import" is enabled in Settings > Newsletters
- Check that the watch folder path matches in both the app and script
- Look at DataPointsAI logs for import errors

### Duplicate Imports

- DataPointsAI deduplicates by sender email and timestamp
- If duplicates appear, check if emails have identical metadata

## Manual Import

You can also import newsletters manually:

1. Export emails as `.eml` files from Mail.app (drag to Finder)
2. In DataPointsAI, go to **Settings > Newsletters**
3. Click **Import .eml Files**
4. Select the exported files

Or drag `.eml` files directly into the watch folder.

## Security Notes

- The AppleScript only reads email content and writes to the specified folder
- No email content is sent to external services during export
- DataPointsAI processes emails locally before any optional summarization
- The script does not modify or delete original emails in Mail.app

## Supported Newsletter Formats

The import handles various newsletter formats:
- HTML newsletters (most common)
- Plain text newsletters
- Multipart emails with both HTML and text
- Newsletters with embedded images (images are preserved as links)

## Common Newsletter Senders

Here are some popular newsletter domains to include in your rules:

- `substack.com` - Substack newsletters
- `beehiiv.com` - Beehiiv newsletters
- `convertkit.com` - ConvertKit newsletters
- `mailchimp.com` - Mailchimp campaigns
- `sendinblue.com` - Brevo/Sendinblue
- `buttondown.email` - Buttondown newsletters
- `ghost.io` - Ghost newsletters
- `revue.co` - Twitter/Revue newsletters

## Advanced: Multiple Rules

You can create multiple rules for different handling:

1. **High-priority newsletters** - Import and auto-summarize
2. **Archive newsletters** - Import only, no summary
3. **Specific topics** - Route to different folders first

Each rule can use the same AppleScript, or you can create variants with different destination folders.
