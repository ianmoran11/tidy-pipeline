-- Converts one XLS or XLSM workbook to XLSX with Microsoft Excel, the way the original
-- package was converted: Excel XML file format (51), macros disabled and links not
-- updated (no prompts), manual calculation with no recalculation before saving (cached
-- source values are kept). Macros are dropped by the XLSX format.
-- Both paths should be inside Excel's sandbox container
-- (~/Library/Containers/com.microsoft.Excel/Data/), so Excel needs no file-access
-- prompt; get_source_data.R copies files in and out.
-- The script only acts on the workbook it opened, by name, and never on a workbook the
-- user has open. It restores the Excel-wide settings it changes (macro security, the
-- links prompt, calculation mode), even when a conversion fails.
-- Usage: osascript sources/convert_with_excel.applescript /abs/input.xls /abs/output.xlsx
on run argv
	set inputPath to item 1 of argv
	set outputFile to (POSIX file (item 2 of argv)) as text
	set inputName to do shell script "basename " & quoted form of inputPath
	set outputName to do shell script "basename " & quoted form of (item 2 of argv)
	tell application "Microsoft Excel"
		set display alerts to false
		set oldAsk to ask to update links
		set oldSecurity to automation security
		set ask to update links to false
		set automation security to msoAutomationSecurityForceDisable
		try
			open (POSIX file inputPath)
			-- wait for the workbook to appear, then act on it by name only
			repeat 60 times
				if (name of every workbook) contains inputName then exit repeat
				delay 1
			end repeat
			if (name of every workbook) does not contain inputName then error "Excel did not open " & inputName
			set wb to workbook inputName
			set oldCalculation to calculation
			set calculation to calculation manual
			set calculate before save to false
			save workbook as wb filename outputFile file format Excel XML file format
			-- after saving, the workbook carries the output's name
			set calculation to oldCalculation
			close workbook outputName saving no
		on error errorText
			set ask to update links to oldAsk
			set automation security to oldSecurity
			error errorText
		end try
		set ask to update links to oldAsk
		set automation security to oldSecurity
	end tell
end run
