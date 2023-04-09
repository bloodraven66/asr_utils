import os
from pathlib import Path
import shutil
ignore = 'asr_stats'
#CAREFUL!!
for foldername in os.listdir('exp'):
    
    if foldername.startswith(ignore): continue
    print(foldername)
    fullpath = os.path.join('exp', foldername)
    dont_delete = []
    all_paths = []
    for filename in os.listdir(fullpath):
        fullfilepath = os.path.join('exp', foldername, filename)
        if os.path.islink(fullfilepath):
            realpath = os.path.realpath(fullfilepath)
            dont_delete.append(Path(realpath).stem)
            dont_delete.append(Path(fullfilepath).stem)
        if filename.endswith('.zip'): 
            all_paths.append(filename)
        if filename.endswith('.pth') and Path(filename).stem not in dont_delete and 'epoch' in filename: 
            all_paths.append(filename)
        if filename == 'att_ws':
            all_paths.append(filename)
    for path in all_paths:
        p = os.path.join(fullpath, path)
        try:
            os.remove(p)
        except:
            shutil.rmtree(p)
    print(all_paths)
        
            
