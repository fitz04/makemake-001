#!/usr/bin/env python3
"""
Generate a simple crater height map for testing texture-based terrain
"""
import math
import random

try:
    from PIL import Image
    import numpy as np
except ImportError:
    print("Installing PIL/Pillow...")
    import subprocess
    subprocess.check_call(['pip3', 'install', 'pillow', 'numpy'])
    from PIL import Image
    import numpy as np

def generate_crater_heightmap(width=1024, height=512, num_craters=50):
    """
    Generate a lunar-like crater heightmap

    Args:
        width: Image width (power of 2 recommended)
        height: Image height (power of 2 recommended)
        num_craters: Number of craters to generate

    Returns:
        PIL Image in grayscale
    """
    # Create base terrain (slightly noisy)
    heightmap = np.ones((height, width), dtype=np.float32) * 0.5

    # Add some base noise
    for y in range(height):
        for x in range(width):
            noise = random.uniform(-0.05, 0.05)
            heightmap[y, x] += noise

    # Generate random craters
    random.seed(42)  # For reproducible results

    for i in range(num_craters):
        # Random crater position
        cx = random.randint(0, width - 1)
        cy = random.randint(0, height - 1)

        # Random crater size
        radius = random.randint(20, 100)

        # Random crater depth
        depth = random.uniform(0.2, 0.5)

        # Optional crater rim
        has_rim = random.random() > 0.3
        rim_height = random.uniform(0.05, 0.15) if has_rim else 0.0

        # Draw crater
        for dy in range(-radius - 10, radius + 10):
            for dx in range(-radius - 10, radius + 10):
                x = cx + dx
                y = cy + dy

                # Wrap around for seamless texture
                x = x % width
                y = y % height

                # Distance from crater center
                dist = math.sqrt(dx*dx + dy*dy)

                if dist < radius:
                    # Inside crater - depression
                    t = dist / radius
                    # Smooth falloff
                    crater_shape = 1.0 - (1.0 - t*t)**2
                    heightmap[y, x] -= depth * crater_shape

                elif has_rim and dist < radius + 10:
                    # Crater rim - slight elevation
                    t = (dist - radius) / 10.0
                    rim_shape = (1.0 - t) * math.exp(-t*2)
                    heightmap[y, x] += rim_height * rim_shape

    # Add one large prominent crater in the south
    large_cx = width // 2
    large_cy = int(height * 0.75)  # Southern hemisphere
    large_radius = 150
    large_depth = 0.6

    print(f"Large crater at: ({large_cx}, {large_cy}), radius: {large_radius}")

    for dy in range(-large_radius - 20, large_radius + 20):
        for dx in range(-large_radius - 20, large_radius + 20):
            x = large_cx + dx
            y = large_cy + dy

            if 0 <= x < width and 0 <= y < height:
                dist = math.sqrt(dx*dx + dy*dy)

                if dist < large_radius:
                    t = dist / large_radius
                    crater_shape = 1.0 - (1.0 - t*t)**2
                    heightmap[y, x] -= large_depth * crater_shape

                elif dist < large_radius + 20:
                    # Large rim
                    t = (dist - large_radius) / 20.0
                    rim_shape = (1.0 - t) * math.exp(-t*2)
                    heightmap[y, x] += 0.2 * rim_shape

    # Normalize to 0-1 range
    heightmap = np.clip(heightmap, 0.0, 1.0)

    # Convert to 8-bit grayscale
    heightmap_8bit = (heightmap * 255).astype(np.uint8)

    # Create PIL Image
    img = Image.fromarray(heightmap_8bit, mode='L')

    return img

if __name__ == "__main__":
    print("Generating crater height map...")

    # Generate 1024x512 height map (2:1 ratio for spherical mapping)
    img = generate_crater_heightmap(1024, 512, num_craters=60)

    output_path = "/home/user/makemake-001/textures/heightmaps/moon_surface.png"
    img.save(output_path)

    print(f"Saved crater height map to: {output_path}")
    print(f"Image size: {img.size}")
    print(f"Image mode: {img.mode}")
    print("\nHeight map legend:")
    print("  White (255) = High terrain")
    print("  Black (0)   = Deep craters")
    print("  Gray (128)  = Base surface")
