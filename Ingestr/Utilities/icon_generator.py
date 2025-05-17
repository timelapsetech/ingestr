#!/usr/bin/env python3
import os
import subprocess
import sys
from pathlib import Path

def create_iconset(svg_path, output_dir):
    """Create PNG files for the asset catalog."""
    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    
    # Define icon sizes and their corresponding filenames
    sizes = {
        16: "icon_16x16.png",
        32: "icon_32x32.png",
        128: "icon_128x128.png",
        256: "icon_256x256.png",
        512: "icon_512x512.png"
    }
    
    # Generate PNG files for each size
    for size, filename in sizes.items():
        # Regular size
        output_file = os.path.join(output_dir, filename)
        subprocess.run([
            "rsvg-convert",
            "-w", str(size),
            "-h", str(size),
            svg_path,
            "-o", output_file
        ])
        
        # 2x size (for high DPI displays)
        if size <= 512:  # Only create 2x versions up to 512x512
            output_file = os.path.join(output_dir, f"icon_{size}x{size}@2x.png")
            subprocess.run([
                "rsvg-convert",
                "-w", str(size * 2),
                "-h", str(size * 2),
                svg_path,
                "-o", output_file
            ])

def create_icns(iconset_dir, output_dir):
    """Convert iconset directory to ICNS file."""
    output_file = os.path.join(output_dir, "Ingestr.icns")
    subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", output_file])
    
    # Clean up iconset directory
    subprocess.run(["rm", "-rf", iconset_dir])

def main():
    # Check if rsvg-convert is installed
    try:
        subprocess.run(["rsvg-convert", "--version"], capture_output=True)
    except FileNotFoundError:
        print("Error: rsvg-convert is not installed.")
        print("Please install librsvg using Homebrew: brew install librsvg")
        sys.exit(1)
    
    # Get the script's directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Set up paths
    svg_path = os.path.join(script_dir, "..", "Resources", "ingestr-icon.svg")
    output_dir = os.path.join(script_dir, "..", "Assets.xcassets", "AppIcon.appiconset")
    
    print("Creating icon PNGs...")
    create_iconset(svg_path, output_dir)
    print(f"Icon PNGs created successfully in: {output_dir}")

if __name__ == "__main__":
    main() 