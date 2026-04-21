"""
Cut Black Edge Off Image Processor

Author: eton
Date: 2026-04-21
Version: v1.0

Objective:
    This script processes image and JSON annotation pairs to remove black edges from images
    and adjust corresponding coordinate annotations. It detects black edges from the first
    image in each folder and applies the same cropping to all images in that folder, updating
    the JSON annotation files accordingly.

Features:
    - Automatic black edge detection using configurable threshold
    - Batch processing of image-JSON pairs with parallel execution
    - Progress tracking with tqdm progress bars
    - Comprehensive safety checks for coordinate validation
    - Support for multiple folder structures (subfolders or single folder)
    - Detailed logging with timestamps
    - Coordinate adjustment for JSON annotations after cropping

Usage:
    Basic usage:
        python cutBlackEdgeOffImage.py /path/to/images/folder

    With custom threshold:
        python cutBlackEdgeOffImage.py /path/to/images/folder --threshold 15

    With parallel workers:
        python cutBlackEdgeOffImage.py /path/to/images/folder --workers 4

    Full options:
        python cutBlackEdgeOffImage.py <folder_path> [--threshold THRESHOLD] [--workers WORKERS]

    Arguments:
        folder_path: Path to the folder containing image and JSON pairs
        --threshold: Threshold for black edge detection (default: 10)
        --workers: Number of parallel workers (default: CPU count)

Requirements:
    - Python 3.7+
    - OpenCV (cv2)
    - NumPy
    - tqdm

Output:
    - Processed images with black edges removed
    - Updated JSON annotation files with adjusted coordinates
    - Log file: CutBlackEdgeOffImage_YYYYMMDD_HHMMSS.log
"""

import os
import json
import argparse
import logging
from datetime import datetime
from pathlib import Path
from concurrent.futures import ProcessPoolExecutor, as_completed
from typing import Tuple, List, Optional
import cv2
import numpy as np
from tqdm import tqdm


def setup_logging():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_filename = f"CutBlackEdgeOffImage_{timestamp}.log"
    
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s',
        handlers=[
            logging.FileHandler(log_filename, encoding='utf-8'),
            #logging.StreamHandler()
        ]
    )
    return logging.getLogger(__name__)


class CutBlackEdgeOffImageProcessor:
    def __init__(self, threshold: int = 10, logger: Optional[logging.Logger] = None):
        self.threshold = threshold
        self.x1: Optional[int] = None
        self.x2: Optional[int] = None
        self.logger = logger or logging.getLogger(__name__)
    
    def detect_black_edges(self, image: np.ndarray) -> Tuple[int, int]:
        height, width = image.shape[:2]
        
        x1 = 0
        x2 = width - 1
        
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
        
        for x in range(width):
            column = gray[:, x]
            if np.mean(column) > self.threshold:
                x1 = x
                break
        
        for x in range(width - 1, -1, -1):
            column = gray[:, x]
            if np.mean(column) > self.threshold:
                x2 = x
                break
        
        return x1, x2
    
    def set_edges_from_first_image(self, image_path: str) -> bool:
        image = cv2.imread(image_path)
        if image is None:
            self.logger.error(f"Failed to read first image: {image_path}")
            return False
        
        self.x1, self.x2 = self.detect_black_edges(image)
        
        if self.x1 is None or self.x2 is None:
            self.logger.error(f"Failed to detect edges in first image: {image_path}")
            return False
        
        if self.x1 < 0:
            self.logger.error(f"Invalid x1 value detected: {self.x1} (must be >= 0)")
            return False
        
        if self.x2 < 0:
            self.logger.error(f"Invalid x2 value detected: {self.x2} (must be >= 0)")
            return False
        
        if self.x1 >= self.x2:
            self.logger.error(f"No valid black edges found in first image: {image_path} (x1={self.x1}, x2={self.x2})")
            return False
        
        height, width = image.shape[:2]
        if self.x2 >= width:
            self.logger.error(f"Invalid x2 value detected: {self.x2} (must be < image width {width})")
            return False
        
        folder_name = Path(image_path).parent.name
        self.logger.info(f"[{folder_name}] Detected edges from first image: x1={self.x1}, x2={self.x2}")
        return True
    
    def process_image_with_json(self, image_path: str, json_path: str) -> bool:
        try:
            if self.x1 is None or self.x2 is None:
                self.logger.error(f"Edges not set. Call set_edges_from_first_image first.")
                return False
            
            if self.x1 < 0:
                self.logger.error(f"Invalid x1 value {self.x1} (must be >= 0) for {image_path}")
                return False
            
            if self.x2 < 0:
                self.logger.error(f"Invalid x2 value {self.x2} (must be >= 0) for {image_path}")
                return False
            
            if self.x1 >= self.x2:
                self.logger.error(f"Invalid edge values x1={self.x1}, x2={self.x2} (x1 must be < x2) for {image_path}")
                return False
            
            image = cv2.imread(image_path)
            if image is None:
                self.logger.error(f"Failed to read image: {image_path}")
                return False
            
            height, width = image.shape[:2]
            
            if self.x2 >= width:
                self.logger.error(f"Invalid x2 value {self.x2} (must be < image width {width}) for {image_path}")
                return False
            
            cropped_image = image[:, self.x1:self.x2+1]
            cv2.imwrite(image_path, cropped_image)
            
            with open(json_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            
            if 'shapes' in data:
                for shape in data['shapes']:
                    if 'points' in shape:
                        for point in shape['points']:
                            if len(point) >= 2:
                                old_x = point[0]
                                new_x = old_x - self.x1
                                
                                if new_x < 0:
                                    self.logger.warning(f"Point x coordinate {old_x} adjusted to 0 for {json_path}")
                                    point[0] = 0
                                else:
                                    point[0] = new_x
            
            with open(json_path, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
            
            self.logger.info(f"Processed: {image_path}")
            return True
        
        except Exception as e:
            self.logger.error(f"Error processing {image_path}: {str(e)}")
            return False
    
    def process_folder(self, folder_path: str, workers: Optional[int] = None) -> int:
        pairs = self.find_image_json_pairs(folder_path)
        
        if not pairs:
            self.logger.warning(f"No image-JSON pairs found in {folder_path}")
            return 0
        
        folder_name = Path(folder_path).name
        self.logger.info(f"Processing folder: {folder_name}")
        self.logger.info(f"Found {len(pairs)} image-JSON pairs")
        
        if not self.set_edges_from_first_image(pairs[0][0]):
            return 0
        
        if self.x1 is None or self.x2 is None:
            self.logger.error("Edges not set properly")
            return 0
        
        success_count = 0
        
        with ProcessPoolExecutor(max_workers=workers) as executor:
            futures = {
                executor.submit(process_pair_with_edges, img_path, json_path, int(self.x1), int(self.x2)): (img_path, json_path)
                for img_path, json_path in pairs
            }
            
            #pbar = tqdm(total=len(pairs), desc=f"Processing {folder_name}", unit="pairs")
            
            for future in as_completed(futures):
                img_path, json_path = futures[future]
                try:
                    if future.result():
                        success_count += 1
                except Exception as e:
                    self.logger.error(f"Error processing {img_path}: {str(e)}")
                
                #pbar.update(1)
            #pbar.close()
        
        self.logger.info(f"Folder {folder_name}: Completed {success_count}/{len(pairs)} pairs")
        return success_count
    
    def find_image_json_pairs(self, folder_path: str) -> List[Tuple[str, str]]:
        folder = Path(folder_path)
        pairs = []
        
        image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.tif'}
        
        for image_file in folder.iterdir():
            if image_file.suffix.lower() in image_extensions:
                json_file = image_file.with_suffix('.json')
                if json_file.exists():
                    pairs.append((str(image_file), str(json_file)))
        
        return pairs


def process_pair_with_edges(image_path: str, json_path: str, x1: int, x2: int) -> bool:
    logger = logging.getLogger(__name__)
    
    try:
        if x1 < 0:
            logger.error(f"Invalid x1 value {x1} (must be >= 0) for {image_path}")
            return False
        
        if x2 < 0:
            logger.error(f"Invalid x2 value {x2} (must be >= 0) for {image_path}")
            return False
        
        if x1 >= x2:
            logger.error(f"Invalid edge values x1={x1}, x2={x2} (x1 must be < x2) for {image_path}")
            return False
        
        image = cv2.imread(image_path)
        if image is None:
            logger.error(f"Failed to read image: {image_path}")
            return False
        
        height, width = image.shape[:2]
        
        if x2 >= width:
            logger.error(f"Invalid x2 value {x2} (must be < image width {width}) for {image_path}")
            return False
        
        cropped_image = image[:, x1:x2+1]
        cv2.imwrite(image_path, cropped_image)
        
        with open(json_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        if 'shapes' in data:
            for shape in data['shapes']:
                if 'points' in shape:
                    for point in shape['points']:
                        if len(point) >= 2:
                            old_x = point[0]
                            new_x = old_x - x1
                            
                            if new_x < 0:
                                logger.warning(f"Point x coordinate {old_x} adjusted to 0 for {json_path}")
                                point[0] = 0
                            else:
                                point[0] = new_x
        
        with open(json_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        
        return True
    
    except Exception as e:
        logger.error(f"Error processing {image_path}: {str(e)}")
        return False


class CutBlackEdgeOffImageAgent:
    def __init__(self, threshold: int = 10, logger: Optional[logging.Logger] = None):
        self.threshold = threshold
        self.logger = logger or logging.getLogger(__name__)
    
    def has_subfolders(self, folder_path: str) -> bool:
        folder = Path(folder_path)
        for item in folder.iterdir():
            if item.is_dir():
                return True
        return False
    
    def has_image_json_pairs(self, folder_path: str) -> bool:
        folder = Path(folder_path)
        image_extensions = {'.jpg', '.jpeg', '.png', '.bmp', '.tiff', '.tif'}
        
        for item in folder.iterdir():
            if item.is_file() and item.suffix.lower() in image_extensions:
                json_file = item.with_suffix('.json')
                if json_file.exists():
                    return True
        return False
    
    def process(self, folder_path: str, workers: Optional[int] = None) -> int:
        if not os.path.isdir(folder_path):
            self.logger.error(f"Error: {folder_path} is not a valid directory")
            return 0
        
        folder_path_obj = Path(folder_path)
        
        if self.has_subfolders(folder_path):
            self.logger.info(f"Found subfolders in {folder_path_obj.name}, processing each subfolder...")
            total_success = 0
            total_folders = 0
            
            all_subfolders = [item for item in folder_path_obj.iterdir() if item.is_dir()]
            subfolders = [item for item in all_subfolders if self.has_image_json_pairs(str(item))]
            
            pbar = tqdm(total=len(subfolders), desc="Processing folders", unit="folders")
            
            for item in all_subfolders:
                if self.has_image_json_pairs(str(item)):
                    self.logger.info(f"Processing subfolder: {item.name}")
                    processor = CutBlackEdgeOffImageProcessor(threshold=self.threshold, logger=self.logger)
                    success_count = processor.process_folder(str(item), workers=workers)
                    total_success += success_count
                    total_folders += 1
                    
                    pbar.update(1)
                else:
                    self.logger.warning(f"Skipping subfolder {item.name}: No image-JSON pairs found")
            
            pbar.close()
            
            self.logger.info(f"Completed processing {total_folders} subfolders: {total_success} pairs processed successfully")
            return total_success
        else:
            if self.has_image_json_pairs(folder_path):
                self.logger.info(f"No subfolders found, processing folder: {folder_path_obj.name}")
                processor = CutBlackEdgeOffImageProcessor(threshold=self.threshold, logger=self.logger)
                success_count = processor.process_folder(folder_path, workers=workers)
                return success_count
            else:
                self.logger.warning(f"No image-JSON pairs found in {folder_path_obj.name}")
                return 0


def main():
    parser = argparse.ArgumentParser(description='Process image and JSON pairs to remove black edges and update coordinates')
    parser.add_argument('folder', type=str, help='Path to the folder containing image and JSON pairs')
    parser.add_argument('--threshold', type=int, default=10, help='Threshold for black edge detection (default: 10)')
    parser.add_argument('--workers', type=int, default=None, help='Number of parallel workers (default: CPU count)')
    
    args = parser.parse_args()
    
    logger = setup_logging()
    logger.info("Starting image processing")
    
    agent = CutBlackEdgeOffImageAgent(threshold=args.threshold, logger=logger)
    success_count = agent.process(args.folder, workers=args.workers)
    
    logger.info(f"Processing complete: {success_count} pairs processed successfully")


if __name__ == '__main__':
    main()