#!/usr/bin/env python3
"""
LabelMe Label Name Finder

A tool to recursively find all unique label names from LabelMe JSON files.
"""

import json
import os
import argparse
import logging
from pathlib import Path
from typing import Set, Dict, List, Optional
import traceback
from tqdm import tqdm
from datetime import datetime


class LabelMeLabelFinder:
    """Class to find unique label names from LabelMe JSON files."""
    
    def __init__(self, base_path: str):
        """
        Initialize the finder with a base path.
        
        Args:
            base_path: The root directory to search for JSON files
        """
        self.base_path = Path(base_path).resolve()
        self.unique_labels: Set[str] = set()
        self.label_first_occurrence: Dict[str, str] = {}  # label -> first file path
        self.base_folders: Set[str] = set()
        self.error_log: List[str] = []
        
        # Setup logging
        self.setup_logging()
    
    def setup_logging(self):
        """Setup logging configuration."""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        log_file = self.base_path / f"label_finder_{timestamp}.log"
        
        # Create file handler for all log levels
        file_handler = logging.FileHandler(log_file, encoding='utf-8')
        file_handler.setLevel(logging.INFO)
        file_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
        
        # Create stream handler for only error and critical levels
        stream_handler = logging.StreamHandler()
        stream_handler.setLevel(logging.ERROR)
        stream_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
        
        logging.basicConfig(
            level=logging.INFO,
            handlers=[
                file_handler,
                stream_handler
            ]
        )
        self.logger = logging.getLogger(__name__)
        self.logger.info(f"LabelMe Label Finder started. Base path: {self.base_path}")
        self.logger.info(f"Log file: {log_file}")
    
    def find_json_files(self) -> List[Path]:
        """
        Recursively find all JSON files in the base path.
        
        Returns:
            List of Path objects for all JSON files found
        """
        json_files = []
        try:
            for root, dirs, files in os.walk(self.base_path):
                for file in files:
                    if file.endswith('.json'):
                        json_path = Path(root) / file
                        json_files.append(json_path)
                        
                        # Track base folders that contain JSON files
                        base_folder = Path(root).name
                        self.base_folders.add(base_folder)
                        
            self.logger.info(f"Found {len(json_files)} JSON files")
            self.logger.info("Base folders containing JSON files:")
            for folder in sorted(self.base_folders):
                self.logger.info(f"  - {folder}")
            
        except Exception as e:
            error_msg = f"Error finding JSON files: {str(e)}"
            self.logger.error(error_msg)
            self.error_log.append(error_msg)
            self.error_log.append(traceback.format_exc())
            
        return json_files
    
    def extract_labels_from_json(self, json_path: Path) -> Set[str]:
        """
        Extract label names from a single JSON file.
        
        Args:
            json_path: Path to the JSON file
            
        Returns:
            Set of unique label names found in the file
        """
        labels_found = set()
        
        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            # Check if 'shapes' key exists and is a list
            if 'shapes' in data and isinstance(data['shapes'], list):
                for shape in data['shapes']:
                    # Check if 'label' key exists in shape
                    if isinstance(shape, dict) and 'label' in shape:
                        label = shape['label']
                        if isinstance(label, str) and label.strip():
                            labels_found.add(label)
                            
                            # Track first occurrence
                            if label not in self.label_first_occurrence:
                                self.label_first_occurrence[label] = str(json_path)
                                self.logger.info(f"First occurrence of label '{label}' found in: {json_path}")
            
            if labels_found:
                self.logger.debug(f"Found labels {list(labels_found)} in {json_path}")
            
        except json.JSONDecodeError as e:
            error_msg = f"JSON decode error in {json_path}: {str(e)}"
            self.logger.error(error_msg)
            self.error_log.append(error_msg)
            self.error_log.append(traceback.format_exc())
            
        except Exception as e:
            error_msg = f"Error processing {json_path}: {str(e)}"
            self.logger.error(error_msg)
            self.error_log.append(error_msg)
            self.error_log.append(traceback.format_exc())
            
        return labels_found
    
    def process_all_files(self):
        """
        Process all JSON files and extract unique labels.
        """
        self.logger.info("Starting to process all JSON files...")
        
        json_files = self.find_json_files()
        
        for i, json_file in enumerate(tqdm(json_files, desc="Processing files", unit="file"), 1):
            try:
                self.logger.info(f"Processing file {i}/{len(json_files)}: {json_file}")
                file_labels = self.extract_labels_from_json(json_file)
                self.unique_labels.update(file_labels)
                
            except Exception as e:
                error_msg = f"Unexpected error processing {json_file}: {str(e)}"
                self.logger.error(error_msg)
                self.error_log.append(error_msg)
                self.error_log.append(traceback.format_exc())
                continue
        
        self.logger.info(f"Processing completed. Found {len(self.unique_labels)} unique labels")
    
    def print_results(self):
        """Print the final results."""
        print("\n" + "="*60)
        print("LABELME LABEL FINDER RESULTS")
        print("="*60)
        
        print(f"\nBase path: {self.base_path}")
        print(f"Total unique labels found: {len(self.unique_labels)}")
        
        
        
        print(f"\nUnique labels (sorted alphabetically):")
        for label in sorted(self.unique_labels):
            print(f"  - {label}")
        
        print(f"\nFirst occurrence of each label:")
        for label in sorted(self.label_first_occurrence.keys()):
            file_path = self.label_first_occurrence[label]
            print(f"  - {label}: {file_path}")
        
        if self.error_log:
            print(f"\nErrors encountered ({len(self.error_log)}):")
            for error in self.error_log:
                print(f"  - {error}")
        else:
            print("\nNo errors encountered during processing.")
        
        print("\n" + "="*60)
    
    def save_results_to_file(self):
        """Save results to a summary file."""
        results_file = self.base_path / "label_finder_results.txt"
        
        try:
            with open(results_file, 'w', encoding='utf-8') as f:
                f.write("LABELME LABEL FINDER RESULTS\n")
                f.write("="*60 + "\n\n")
                
                f.write(f"Base path: {self.base_path}\n")
                f.write(f"Total unique labels found: {len(self.unique_labels)}\n\n")
                
                f.write("Base folders containing JSON files:\n")
                for folder in sorted(self.base_folders):
                    f.write(f"  - {folder}\n")
                
                f.write(f"\nUnique labels (sorted alphabetically):\n")
                for label in sorted(self.unique_labels):
                    f.write(f"  - {label}\n")
                
                f.write(f"\nFirst occurrence of each label:\n")
                for label in sorted(self.label_first_occurrence.keys()):
                    file_path = self.label_first_occurrence[label]
                    f.write(f"  - {label}: {file_path}\n")
                
                if self.error_log:
                    f.write(f"\nErrors encountered ({len(self.error_log)}):\n")
                    for error in self.error_log:
                        f.write(f"  - {error}\n")
                else:
                    f.write("\nNo errors encountered during processing.\n")
            
            self.logger.info(f"Results saved to: {results_file}")
            
        except Exception as e:
            error_msg = f"Error saving results to file: {str(e)}"
            self.logger.error(error_msg)
            self.error_log.append(error_msg)
            self.error_log.append(traceback.format_exc())


def main():
    """Main function to run the LabelMe Label Finder."""
    parser = argparse.ArgumentParser(
        description="Find all unique label names from LabelMe JSON files recursively",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python labelme_label_finder.py /path/to/labelme/data
  python labelme_label_finder.py ./data_folder
  python labelme_label_finder.py /home/user/labelme_project
        """
    )
    
    parser.add_argument(
        'input_path',
        help='Path to the folder containing LabelMe JSON files'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Enable verbose logging'
    )
    
    args = parser.parse_args()
    
    # Validate input path
    input_path = Path(args.input_path)
    if not input_path.exists():
        print(f"Error: Input path '{input_path}' does not exist.")
        return 1
    
    if not input_path.is_dir():
        print(f"Error: Input path '{input_path}' is not a directory.")
        return 1
    
    try:
        # Create and run the finder
        finder = LabelMeLabelFinder(str(input_path))
        finder.process_all_files()
        finder.print_results()
        finder.save_results_to_file()
        
        return 0
        
    except KeyboardInterrupt:
        print("\nOperation cancelled by user.")
        return 1
        
    except Exception as e:
        print(f"Unexpected error: {str(e)}")
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    exit(main())