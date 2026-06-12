import os
import json

def extract_english_label(text):
    """Splits by the last colon and returns the English part."""
    if isinstance(text, str) and ':' in text:
        return text.rsplit(':', 1)[-1].strip()
    return text

def process_json_folder(folder_path):
    if not os.path.exists(folder_path):
        print(f"Error: Path '{folder_path}' not found.")
        return

    # 1. Collect all JSON files first to get the total count
    json_files = []
    for root, _, files in os.walk(folder_path):
        for file in files:
            if file.endswith('.json'):
                json_files.append(os.path.join(root, file))
    
    total_files = len(json_files)
    if total_files == 0:
        print("No JSON files found.")
        return

    print(f"Found {total_files} files. Starting processing...\n")

    modified_count = 0
    
    for index, file_path in enumerate(json_files, 1):
        # Print progress for every file
        print(f"[{index}/{total_files}] Processing...", end='\r')
        
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            file_was_modified = False

            # Recursive function to find all 'label' keys
            def update_labels(obj):
                nonlocal file_was_modified
                if isinstance(obj, dict):
                    for key, value in obj.items():
                        if key == 'label' and isinstance(value, str):
                            new_val = extract_english_label(value)
                            if new_val != value:
                                obj[key] = new_val
                                file_was_modified = True
                        else:
                            update_labels(value)
                elif isinstance(obj, list):
                    for item in obj:
                        update_labels(item)

            update_labels(data)

            if file_was_modified:
                modified_count += 1
                with open(file_path, 'w', encoding='utf-8') as f:
                    json.dump(data, f, ensure_ascii=False, indent=4)
                
                # Only print the specific filename for the first 3 modified files
                if modified_count <= 3:
                    # Clear the progress line to print the specific file info
                    print(f"Cleaned labels in: {os.path.basename(file_path)}          ")

        except Exception as e:
            print(f"\nError processing {os.path.basename(file_path)}: {e}")

    print(f"\n\nTask complete!")
    print(f"Total files scanned: {total_files}")
    print(f"Total files modified: {modified_count}")

if __name__ == "__main__":
    folder = input("Enter the folder path: ").strip()
    process_json_folder(folder)
