#!/bin/bash
# extract_invoice_info.sh - Robust version, processes all PDFs even if some fail

# ---------- Configuration ----------
DEFAULT_INPUT_DIR="."
DEFAULT_OUTPUT_CSV="invoices.csv"
DEFAULT_LOG_FILE="extract_invoice.log"
LOG_LEVEL="INFO"   # DEBUG, INFO, WARN, ERROR

# ---------- Logging ----------
log() {
    local level="$1"; local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Filter by LOG_LEVEL
    case "$LOG_LEVEL" in
        DEBUG) ;;  # log everything
        INFO)  [[ "$level" == "DEBUG" ]] && return ;;
        WARN)  [[ "$level" =~ ^(DEBUG|INFO)$ ]] && return ;;
        ERROR) [[ "$level" != "ERROR" ]] && return ;;
    esac
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}
log_debug() { log "DEBUG" "$1"; }
log_info()  { log "INFO"  "$1"; }
log_warn()  { log "WARN"  "$1"; }
log_error() { log "ERROR" "$1"; }

# ---------- Help ----------
usage() {
    cat << EOF
Usage: $0 [input_dir] [output_csv] [log_file]

Extract invoice number, date, and amount from PDF invoices.
EOF
    exit 0
}

# ---------- Main ----------
main() {
    INPUT_DIR="${1:-$DEFAULT_INPUT_DIR}"
    OUTPUT_CSV="${2:-$DEFAULT_OUTPUT_CSV}"
    LOG_FILE="${3:-$DEFAULT_LOG_FILE}"

    if [[ ! -d "$INPUT_DIR" ]]; then
        echo "ERROR: Directory '$INPUT_DIR' does not exist."
        usage
    fi

    touch "$LOG_FILE"
    log_info "===== Invoice extraction started ====="
    log_info "Input directory: $(realpath "$INPUT_DIR")"
    log_info "Output CSV: $OUTPUT_CSV"
    log_info "Log file: $LOG_FILE"

    # Check dependencies
    if ! command -v pdftotext &> /dev/null; then
        log_error "pdftotext not found. Install poppler-utils: sudo apt install poppler-utils"
        exit 1
    fi

    # Find PDFs (robust, handles spaces and special characters)
    pdf_files=()
    while IFS= read -r -d '' file; do
        pdf_files+=("$file")
    done < <(find "$INPUT_DIR" -maxdepth 1 -type f -iname "*.pdf" -print0|sort -z)

    pdf_count=${#pdf_files[@]}
    log_info "Found $pdf_count PDF file(s) in $INPUT_DIR"

    if [[ $pdf_count -eq 0 ]]; then
        log_warn "No PDF files found. Exiting."
        exit 0
    fi

    # Initialize CSV
    echo "\"filename\",\"invoice_number\",\"date\",\"amount\"" > "$OUTPUT_CSV"
    log_info "CSV initialized: $OUTPUT_CSV"

    # Process each PDF (no 'set -e' inside loop)
    success_count=0
    for pdf in "${pdf_files[@]}"; do
        filename=$(basename "$pdf")
        log_info "Processing: $filename"

        # Extract text; do NOT exit if pdftotext fails
        text=$(pdftotext -layout -enc UTF-8 "$pdf" - 2>/dev/null) || {
            log_error "  Failed to extract text from $filename (maybe scanned or corrupted)"
            printf '"%s","%s","%s","%s"\n' "$filename" "EXTRACTION_FAILED" "EXTRACTION_FAILED" "EXTRACTION_FAILED" >> "$OUTPUT_CSV"
            continue
        }

        # If text is empty, log and skip
        if [[ -z "$text" ]]; then
            log_warn "  No text content in $filename (may be image‑only PDF)"
            printf '"%s","%s","%s","%s"\n' "$filename" "NO_TEXT" "NO_TEXT" "NO_TEXT" >> "$OUTPUT_CSV"
            continue
        fi

        # Extract fields (using same regex as before)
        invoice_num=$(echo "$text" | grep -oP '发票号码[：:]\s*\K\d+' | head -1)
        invoice_num=${invoice_num:-NOT_FOUND}

        date_raw=$(echo "$text" | grep -oP '开票日期[：:]\s*\K\d{4}年\d{1,2}月\d{1,2}日' | head -1)
        if [[ -n "$date_raw" ]]; then
            date=$(echo "$date_raw" | sed -E 's/([0-9]{4})年([0-9]{1,2})月([0-9]{1,2})日/\1-\2-\3/' | sed -E 's/\b([0-9])\b/0\1/g')
        else
            date="NOT_FOUND"
        fi

        # Amount extraction (multiple patterns)
        amount="NOT_FOUND"
        # Pattern 1: 价税合计/合计/总金额 followed by ¥ or ￥
        amount=$(echo "$text" | grep -oP '(价税合计|合计|总金额)[^¥￥0-9]*[¥￥]\s*\K\d+(?:\.\d{1,2})?' | head -1)
        # Pattern 2: standalone ¥/￥ at line end
        [[ "$amount" == "NOT_FOUND" ]] && amount=$(echo "$text" | grep -oP '[¥￥]\s*\K\d+(?:\.\d{1,2})?' | tail -1)
        # Pattern 3: 小写 field
        [[ "$amount" == "NOT_FOUND" ]] && amount=$(echo "$text" | grep -oP '小写[：:]\s*[¥￥]?\s*\K\d+(?:\.\d{1,2})?' | head -1)
        # Pattern 4: any currency symbol with two decimals
        [[ "$amount" == "NOT_FOUND" ]] && amount=$(echo "$text" | grep -oP '[¥￥]\s*\K\d+\.\d{2}' | head -1)

        # Normalize decimal places
        if [[ "$amount" != "NOT_FOUND" && ! "$amount" =~ \. ]]; then
            amount="${amount}.00"
        fi

        printf '"%s","%s","%s","%s"\n' "$filename" "$invoice_num" "$date" "$amount" >> "$OUTPUT_CSV"
        log_info "  -> Invoice: $invoice_num, Date: $date, Amount: $amount"
        ((success_count++))
    done

    log_info "Processed $pdf_count PDF(s), successfully extracted data from $success_count file(s)."
    log_info "===== CSV written to $OUTPUT_CSV ====="
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage; fi
main "$@"
