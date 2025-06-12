const fs = require('fs-extra');
const path = require('path');

async function copyTokenyFiles() {
  const sourceDir = path.join(__dirname, '..', 'node_modules', '@tokenysolutions');
  const destDir = path.join(__dirname, '..', 'contracts', 'lib', '@tokenysolutions');
  
  try {
    // Ensure the destination directory exists
    await fs.ensureDir(destDir);
    
    // Copy the t-rex package
    await fs.copy(
      path.join(sourceDir, 't-rex'),
      path.join(destDir, 't-rex')
    );
    
    console.log('Successfully copied Tokeny files to contracts/lib/@tokenysolutions');
  } catch (err) {
    console.error('Error copying Tokeny files:', err);
    process.exit(1);
  }
}

copyTokenyFiles();
