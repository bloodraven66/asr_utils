import torch
import torchaudio
import argparse
import os
from pathlib import Path
import random
import numpy as np
from tqdm import tqdm
import csv

#https://pytorch.org/audio/main/tutorials/squim_tutorial.html#sphx-glr-tutorials-squim-tutorial-py

try:
    from torchaudio.prototype.pipelines import SQUIM_OBJECTIVE
    from torchaudio.prototype.pipelines import SQUIM_SUBJECTIVE
    from pesq import pesq
    from pystoi import stoi
except ImportError:
    print(
        """
        To enable running this notebook in Google Colab, install nightly
        torch and torchaudio builds by adding the following code block to the top
        of the notebook before running it:
        !pip3 uninstall -y torch torchvision torchaudio
        !pip3 install --pre torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/nightly/cpu
        !pip3 install pesq
        !pip3 install pystoi
        """
    
    )
    exit()
import torchaudio.functional as F
from torchaudio.utils import download_asset
from IPython.display import Audio
import matplotlib.pyplot as plt


parser = argparse.ArgumentParser()
parser.add_argument('--folder', required=True)
parser.add_argument('--reference_list_path', required=True)
parser.add_argument('--reference_path', required=True)
parser.add_argument('--load_folder', default="samples")
parser.add_argument('--save_folder', default="metrics")

def load_audio(path, required_sr=16000):
    audio, sr = torchaudio.load(path)
    if sr != required_sr:
        audio = F.resample(audio, sr, 16000)
    return audio

def get_metrics(pred_file, ref_files, num_repeats=20):
    pred = load_audio(pred_file)
    stoi_hyp, pesq_hyp, si_sdr_hyp = objective_model(pred[0:1, :])
    mos = []
    for x in range(num_repeats):
        ref_ = random.choice(ref_files)
        ref_ = load_audio(ref_)
        mos.append(subjective_model(pred[0:1, :], ref_[0:1, :]).item())
    return {"name":Path(pred_file).stem, "stoi":stoi_hyp.item(), "pesq":pesq_hyp.item(), "si_sdr":si_sdr_hyp.item(), "mos_mean":np.mean(mos), "mos_std":np.std(mos)}

def write_results(results, savename):
    with open(savename, 'w', newline='',) as csvfile:
        fieldnames = list(results[0].keys())
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames, delimiter="\t")
        writer.writeheader()
        for x in results:
            writer.writerow(x)
            

def predict(pred_files, ref_files, savename, num_repeats=10):
    args = parser.parse_args()
    objective_model = SQUIM_OBJECTIVE.get_model()
    subjective_model = SQUIM_SUBJECTIVE.get_model()
    
    results = []
    for pred_file in tqdm(pred_files):
        
        pred = load_audio(pred_file)
        stoi_hyp, pesq_hyp, si_sdr_hyp = objective_model(pred[0:1, :])
        mos = []
        for x in range(num_repeats):
            ref_ = random.choice(ref_files)
            ref_ = load_audio(ref_)
            mos.append(subjective_model(pred[0:1, :], ref_[0:1, :]).item())
        res = {"name":Path(pred_file).stem, "stoi":stoi_hyp.item(), "pesq":pesq_hyp.item(), "si_sdr":si_sdr_hyp.item(), "mos_mean":np.mean(mos), "mos_std":np.std(mos)}
        
        results.append(res)
    write_results(results, savename)
    
    
