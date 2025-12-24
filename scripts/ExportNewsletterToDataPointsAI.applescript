(*
    Export Newsletter to DataPointsAI

    This AppleScript is designed to work with Mail.app rules to automatically
    export newsletter emails to the DataPointsAI watch folder.

    SETUP INSTRUCTIONS:
    1. Open Script Editor and save this as an application or script
    2. Open Mail.app → Settings → Rules
    3. Create a new rule with your newsletter conditions
    4. Set the action to "Run AppleScript" and select this script

    CONFIGURATION:
    Edit the destinationFolder below to match your DataPointsAI
    newsletter watch folder (Settings → Newsletters → Watch Folder)
*)

-- Configuration: Set this to your DataPointsAI newsletter folder
property destinationFolder : "~/Documents/DataPointsAI Newsletters/"

-- Main handler for Mail.app rules
on perform mail action with messages theMessages
    -- Ensure destination folder exists
    set expandedPath to do shell script "echo " & quoted form of destinationFolder
    do shell script "mkdir -p " & quoted form of expandedPath

    repeat with theMessage in theMessages
        try
            -- Get message details
            set theSubject to subject of theMessage
            set theSender to sender of theMessage
            set theDate to date received of theMessage

            -- Create a safe filename from subject
            -- Remove characters that are invalid in filenames
            set cleanSubject to my sanitizeFilename(theSubject)

            -- Add timestamp to prevent duplicates
            set theTimestamp to do shell script "date +%Y%m%d%H%M%S"

            -- Build the filename
            set fileName to cleanSubject & "_" & theTimestamp & ".eml"
            set fullPath to expandedPath & fileName

            -- Get the raw message source (RFC 822 format)
            set theSource to source of theMessage

            -- Write to file
            -- Using shell script to handle special characters properly
            set tempFile to do shell script "mktemp"
            do shell script "cat > " & quoted form of tempFile & " <<'EOFMARKER'\n" & theSource & "\nEOFMARKER"
            do shell script "mv " & quoted form of tempFile & " " & quoted form of fullPath

            -- Log success
            log "Exported: " & fileName

        on error errMsg
            -- Log error but continue with other messages
            log "Error exporting message: " & errMsg
        end try
    end repeat
end perform mail action with messages

-- Helper function to sanitize filename
on sanitizeFilename(inputText)
    -- Remove or replace characters that are invalid in filenames
    set invalidChars to {"/", ":", "*", "?", "\"", "<", ">", "|", "\\"}
    set outputText to inputText

    repeat with invalidChar in invalidChars
        set AppleScript's text item delimiters to invalidChar
        set textItems to text items of outputText
        set AppleScript's text item delimiters to "-"
        set outputText to textItems as text
    end repeat

    set AppleScript's text item delimiters to ""

    -- Trim to reasonable length (max 100 chars)
    if length of outputText > 100 then
        set outputText to text 1 thru 100 of outputText
    end if

    -- Remove leading/trailing whitespace
    set outputText to do shell script "echo " & quoted form of outputText & " | xargs"

    -- If empty after sanitization, use a default name
    if outputText is "" then
        set outputText to "newsletter"
    end if

    return outputText
end sanitizeFilename

-- For testing: Run this script directly to test with selected messages
on run
    tell application "Mail"
        set selectedMessages to selection
        if (count of selectedMessages) > 0 then
            my perform mail action with messages selectedMessages
            display dialog "Exported " & (count of selectedMessages) & " message(s) to " & destinationFolder buttons {"OK"} default button "OK"
        else
            display dialog "No messages selected. Select one or more messages in Mail.app to test." buttons {"OK"} default button "OK"
        end if
    end tell
end run
