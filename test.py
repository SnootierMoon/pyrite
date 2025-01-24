import numpy as np
from PIL import Image

# Define image dimensions
width = 512
height = 128
for s in ["mine", "theirs"]:
    # Read raw RGBA data from file
    with open(s + '.txt', 'rb') as f:
        raw_data = f.read()
    
    # Convert raw bytes to numpy array
    # reshape to (height, width, 4) for RGBA channels
    image_array = np.frombuffer(raw_data, dtype=np.uint8).reshape((height, width, 4))
    
    # Create PIL image from numpy array
    image = Image.fromarray(image_array, 'RGBA')
    
    # Save as PNG
    image.save(s + '.png')
    
