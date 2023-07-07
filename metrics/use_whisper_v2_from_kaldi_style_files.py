import os
from tqdm import tqdm
import argparse
from pathlib import Path
from transformers import WhisperProcessor, WhisperForConditionalGeneration
from datasets import load_dataset
import librosa
import jiwer
import torch

parser = argparse.ArgumentParser()
parser.add_argument("--lang", required=True)
parser.add_argument("--savepath", default="results/whisper_v2_asru_test_")
parser.add_argument("--infer", default=False)

data_path = {"bn":"/home1/Sathvik/fairseq_datasets/asru_final_test_set/test_bn_asru/",
             "bh":"/home1/Sathvik/fairseq_datasets/asru_final_test_set/test_bh_asru/"
             }
lang_mapping = {"bn":"bn",
                "bh":"hi"}

def infer():
    with open(os.path.join(data_path[args.lang], "text"), 'r') as f:
        lines = f.read().split('\n')[:-1]
    lines = {'_'.join(l.split(' ')[0].split('_')[2:]):' '.join(l.split(' ')[1:]) for l in lines}
    savepath = args.savepath+args.lang
    ref, hyp = [], []
    for fname in os.listdir(savepath):
        with open(os.path.join(savepath, fname), 'r') as f:
            data = f.read().split('\n')[:-1]
        id, text = data[0].split('\t')
        
        text = text.strip()
        assert id in lines
        ref.append(lines[id])
        hyp.append(text)
    wer = jiwer.wer(ref, hyp)
    cer  =jiwer.cer(ref, hyp)
    print(len(lines), len(hyp))
    print(wer, cer)
    
def main(sr=16000, model_name="openai/whisper-large-v2"):
    with open(os.path.join(data_path[args.lang], "wav.scp"), 'r') as f:
        wavs = f.read().split('\n')[:-1]
    wavs = [w.split(' ')[-1] for w in wavs]
    savepath = args.savepath+args.lang
    if not os.path.exists(savepath): os.mkdir(savepath)
    done_files = os.listdir(savepath)
    done_files = set([Path(f).stem for f in done_files])
    todo_files = [f for f in wavs if Path(f).stem not in done_files]
    print(f"Total files - {len(wavs)}")
    print(f"Todo files - {len(todo_files)}")
    
    processor = WhisperProcessor.from_pretrained(model_name)
    model = WhisperForConditionalGeneration.from_pretrained(model_name)

    for wav in tqdm(wavs):
        data = torch.from_numpy(librosa.load(wav, sr)[0])
        inputs = processor.feature_extractor(data, return_tensors="pt", sampling_rate=sr).input_features
        predicted_ids = model.generate(inputs, language=f"<|{lang_mapping[args.lang]}|>", task="transcribe")
        out = processor.tokenizer.batch_decode(predicted_ids, skip_special_tokens=True)[0]
        savename = os.path.join(savepath, Path(wav).stem)+'.txt'
        with open(savename, 'w') as f: f.write(Path(wav).stem + '\t' + out + '\n')
        
if __name__ == "__main__":
    args = parser.parse_args()
    if args.infer:
        print("Infer mode")
        infer()
        exit()
    main()