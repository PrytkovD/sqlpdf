#Requires -Version 5
param (
    [string]$dbname,
    [string]$username,
    [string]$output,
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string]$remaining = ""
)

Set-StrictMode -Off

function get_file_contentes_split_by_line($filename) {
    if (-not(Test-Path -Path $filename -PathType Leaf)) {
        Write-Host "ERROR: File '$filename' does not exist" -ForegroundColor Red
        return $null
    }
    $string = Get-Content $arg | Out-String
    $nl = [System.Environment]::NewLine
    $items = ($string -split "$nl$nl")

    $items
}

function pipe_table_to_grid_table($pipe_table) {
    [string[]] $lines = $pipe_table.Split([Environment]::NewLine, [StringSplitOptions]::RemoveEmptyEntries)

    $pipe_separator = $lines[1]

    $grid_separator = "+$($pipe_separator)+"
    $grid_headings_separator = $grid_separator.Replace('-', '=')

    $grid_table_lines = [System.Collections.ArrayList][string[]]@()
    $grid_table_lines += $grid_separator
    $grid_table_lines += "|$($lines[0])|"

    if ($lines.Count -ne 2) {
        $grid_table_lines += $grid_headings_separator

        for ($i = 2; $i -lt $lines.Count; $i++) {
            $grid_table_lines += "|$($lines[$i])|"
            $grid_table_lines += $grid_separator
        }
    } else {
        $grid_table_lines += $grid_separator
    }

    $grid_table = $grid_table_lines -join [Environment]::NewLine

    $grid_table
}

$args = $remaining.Split(' ');

$curdir = Get-Location
$arg0 = $args[0]

if ($arg0 -in @($null, '', '-h', '--help')) {
    Write-Host "Использование: sqlpdf [-dbname DatabaseName] [-username UserName] [-output outputName] file [files...]"
    exit 0
}

if ($dbname -eq '') {
    $dbname = $(Read-Host "Введите имя базы данных")
}

if ($username -eq '') {
    $username = $(Read-Host "Введите имя пользователя")
}

if ($output -eq '') {
    $output = $(Read-Host "Введите имя выходного файла без расширения (будут созданы два файла: .md и .pdf)")
    $output = Join-Path -Path $curdir -ChildPath $output
}

$queries = [System.Collections.ArrayList]@()

foreach ($arg in $args) {
    $file = Join-Path -Path $curdir -ChildPath $arg

    Write-Host "Обрабатываю файл '$file'"
    $items = get_file_contentes_split_by_line($file)

    if ($items -ne $null) {
        foreach ($item in $items) {
            if ($item.ToLower().StartsWith("select") -or $item.ToLower().StartsWith("update") -or $item.ToLower().StartsWith("delete")) {
                $queries += $item
            } elseif ($item.StartsWith("--")) {
            } else {
                & psql -U $username -d $dbname -c "$item" -q
            }
        }
    }
}

$markdown = ''

$index = 1

$outmd = -join($output, ".md")
$outpdf = -join($output, ".pdf")

foreach ($query in $queries) {
    $cmdoutput = (psql -U $username -d $dbname -c "$query" -q) | Out-String

    if ($cmdoutput -eq '') {
        continue
    }

    $cmdoutput = $cmdoutput -replace '\(.*\)',''
    $cmdoutput = pipe_table_to_grid_table $cmdoutput

    $markdown = -join($markdown, "## $index`n`n")
    $markdown = -join($markdown, "``````sql`n")
    $markdown = -join($markdown, "$query`n")
    $markdown = -join($markdown, "```````n`n")
    $markdown = -join($markdown, "$cmdoutput`n`n")

    $index++
}

$markdown | Out-File -FilePath $outmd;

#curl -s --data-urlencode "markdown=$markdown" --output $outpdf https://md-to-pdf.fly.dev
curl -s --data-urlencode "markdown=$markdown" --data-urlencode "css=@page {size: A4 landscape;} table {font-size: 8pt; border-collapse: collapse;} th,td {border-bottom: 1px solid gray;} @media print {h2 {page-break-before: always;}}" --output $outpdf https://md-to-pdf.fly.dev