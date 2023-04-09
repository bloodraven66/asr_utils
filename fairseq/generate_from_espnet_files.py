import os, sys
from pathlib import Path
import soundfile
import argparse
from tqdm import tqdm
from multiprocessing import Pool

#https://github.com/facebookresearch/fairseq/issues/2819
#https://github.com/facebookresearch/fairseq/issues/2654

parser = argparse.ArgumentParser()
parser.add_argument('--folder', required=True)
parser.add_argument('--save_folder', required=True)
parser.add_argument('--tag', required=True)
parser.add_argument('--sr', default=16000)
parser.add_argument('--save_dict', action='store_true', default=False)
parser.add_argument('--nj', default=64)
parser.add_argument('--text_prep', action='store_true', default=False)
parser.add_argument('--wav_prep', action='store_true', default=False)
parser.add_argument('--dialect_map', action='store_true', default=False)
parser.add_argument('--dialect_info', default='utt2dialect')
parser.add_argument('--dialect_id', default=None)
parser.add_argument('--frame_loc', default=None)
parser.add_argument('--duration_per_dialect', default=None)
parser.add_argument('--filter_by_duration', action='store_true', default=False)
parser.add_argument('--lexicon', action='store_true', default=False)
parser.add_argument('--dir_path', default='.')

def check_files():
    files = os.listdir(args.folder)
    assert 'wav.scp' in files
    assert 'text' in files
    assert args.tag in ['train', 'valid', 'test']

def extract_letter_and_word(ids):
    with open(os.path.join(args.folder, 'text'), 'r') as f:
        lines = f.read().split('\n')[:-1]
    words, letters = [], []
    letter_dict = {}
    for line in tqdm(lines):
        id = line.split(' ')[0].split('_')[-1]
        if ids is not None:
            if id not in ids:
                continue
        text = ' '.join(line.split(' ')[1:]).strip().split(' ')
        letter_dict['|'] = 1
        for ch in ' '.join(text):
            if ch == ' ': continue
            if ch not in letter_dict: letter_dict[ch] = 0
            letter_dict[ch] += 1
        words.append(' '.join(text).strip())
        letters.append(' '.join(list('|'.join(text)))+' |')
    print(f'num of lines found:', len(letters))
    return words, letters, letter_dict

def save_text_metatdata(data):
    words, letters, letter_dict = data
    if not os.path.exists(os.path.join(args.save_folder, args.tag)): 
        os.makedirs(os.path.join(args.save_folder, args.tag))
    word_save_path = os.path.join(args.save_folder, args.tag+'.wrd')
    letter_save_path = os.path.join(args.save_folder, args.tag+'.ltr')
    print(f'saving word metadata: {word_save_path}')
    print(f'saving letter metadata: {letter_save_path}')
    with open(word_save_path, 'w') as f:
        for line in words:
            f.write(line+'\n')
    with open(letter_save_path, 'w') as f:
        for line in letters:
            f.write(line+'\n')
    
    if args.save_dict:
        letter_dict_save_path = os.path.join(args.save_folder, 'dict.ltr.txt')
        with open(letter_dict_save_path, 'w') as f:
            for key in letter_dict:
                if key == ' ': continue
                f.write(f'{key} {letter_dict[key]}\n')
    
    if args.lexicon:
        lexicon_save_path = os.path.join(args.save_folder, 'lexicon.lst')
        word_dict = {}
        for line in words:
            for word in line.split(' '):
                if word not in word_dict: word_dict[word] = ' '.join(list(word))+' |'
        with open(lexicon_save_path, 'w') as f:
            for word in word_dict:
                f.write(f'{word}\t{word_dict[word]}\n')
                
def save_wav_metatdata(data):
    wavs, frames = data
    wav_save_path = os.path.join(args.save_folder, args.tag+'.tsv')
    print(f'saving wav metadata: {wav_save_path}')
    with open(wav_save_path, 'w') as f:
        f.write(args.dir_path+'\n')
        for idx in range(len(wavs)):
            f.write(f'{wavs[idx]}\t{frames[idx]}\n')


def make_manifest(ids):
    
    with open(os.path.join(args.folder, 'wav.scp'), 'r') as f:
        lines = f.read().split('\n')[:-1]
    wavs = [l.split(' ')[-1] for l in lines]
    if ids is not None:
        wavs = [w for w in wavs if Path(w).stem in ids]
    print(f'num of lines found:', len(wavs))
    with Pool(args.nj) as p:
        frames = list(tqdm(p.imap(get_frames, wavs), total=len(wavs)))
    return wavs, frames

def get_frames(path):
   frames = soundfile.info(path).frames
   return frames 

def filter_keys_by_duration():
    print('filtering')
    with open(args.dialect_id, 'r') as f:
        dialect_ids = f.read().split('\n')[:-1]
    dialect_ids = {d.split(' ')[1]:d.split(' ')[0] for d in dialect_ids}
    
    with open(args.frame_loc, 'r') as f:
        frames = f.read().split('\n')[:-1]
    frames = {Path(f.split('\t')[0]).stem:float(f.split('\t')[1])/args.sr for f in frames}
    duration_per_dialect = {}
    ids = []
    for wavid in tqdm(dialect_ids):
        dur = frames[wavid]
        dialect = dialect_ids[wavid]
        if dialect not in duration_per_dialect: duration_per_dialect[dialect] = []
        if sum(duration_per_dialect[dialect])/3600 > float(args.duration_per_dialect) :
            continue
        duration_per_dialect[dialect].append(dur)
        ids.append(wavid)
    for d in duration_per_dialect:
        print(d, round(sum(duration_per_dialect[d])/3600,2), len(duration_per_dialect[d]))
    print('total utts:',len(ids))
    ids = set(ids)
    return ids
        
def retrieve_dialect_map():
    with open(os.path.join(args.folder, args.dialect_info), 'r') as f:
        lines = f.read().split('\n')
    return {l.split('\t')[0]:l.split('\t')[1] for l in lines if len(l)>0}

def save_dialect_mapping(dialects):
    with open(os.path.join(args.save_folder, args.tag+'.tsv'), 'r') as f:
        data = f.read().split('\n')
    dialect_data  = {Path(l.split('\t')[0]).stem:dialects[Path(l.split('\t')[0]).stem] for l in data[1:-1]}
    assert len(data) == len(dialect_data) + 2
    with open(os.path.join(args.save_folder, args.dialect_info), 'w') as f:
        for l in dialect_data:
            f.write(l+'\t'+dialect_data[l]+'\n')
            
def main():
    check_files()
    ids = None
    if args.filter_by_duration:
        ids = filter_keys_by_duration()
        
    if args.text_prep:
        data = extract_letter_and_word(ids)
        save_text_metatdata(data)
    if args.wav_prep:
        data = make_manifest(ids)
        save_wav_metatdata(data)
    if args.dialect_map:
        dialects = retrieve_dialect_map()
        save_dialect_mapping(dialects)
        
if __name__ == '__main__':
    args = parser.parse_args()

    main()