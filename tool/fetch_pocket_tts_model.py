#!/usr/bin/env python3
"""Baixa e prepara o Pocket TTS português usado pelo aplicativo.

Os arquivos grandes não são versionados. Este script fixa as revisões de
origem, verifica cada download por tamanho e SHA-256 e converte o tokenizer
SentencePiece para o formato consumido pelo sherpa-onnx.

O bundle português exige um embedding BOS antes das latentes da voz de
referência (`insert_bos_before_voice` no bundle.json de origem). O sherpa-onnx
1.13.8 não conhece esse passo e, sem ele, o modelo gera só ruído. Por isso o
BOS é embutido no encoder Mimi: a saída `latents` passa a começar por ele.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path


MODEL_REPOSITORY = "KevinAHM/pocket-tts-onnx"
MODEL_REVISION = "58a6d00cf13d239b6748cb0769f35c580a8f606c"
MODEL_PREFIX = "onnx/portuguese"

# Voz "rafael" (pt) do catálogo oficial; a revisão é a mesma fixada em
# pocket_tts/utils/utils.py. O repositório é restrito: exige aceitar os termos
# em https://huggingface.co/kyutai/pocket-tts e um token do Hugging Face.
VOICE_REPOSITORY = "kyutai/pocket-tts"
VOICE_REVISION = "64ab7d24c479d736a83b8cc666c4a776fca30fda"
VOICE_PATH = "g-Vi8PgmSY0-enhanced-v2.wav"


@dataclass(frozen=True)
class Artifact:
    repository: str
    revision: str
    remote_path: str
    local_name: str
    size: int
    sha256: str

    @property
    def url(self) -> str:
        return (
            f"https://huggingface.co/{self.repository}/resolve/"
            f"{self.revision}/{self.remote_path}?download=true"
        )


ARTIFACTS = (
    Artifact(
        MODEL_REPOSITORY,
        MODEL_REVISION,
        f"{MODEL_PREFIX}/flow_lm_flow_int8.onnx",
        "flow_lm_flow_int8.onnx",
        9_962_530,
        "53c50fc75f892687920c316513715bfbefbdb3b7642786e287c7971df53edb26",
    ),
    Artifact(
        MODEL_REPOSITORY,
        MODEL_REVISION,
        f"{MODEL_PREFIX}/flow_lm_main_int8.onnx",
        "flow_lm_main_int8.onnx",
        76_341_079,
        "119e5ce926cadc273508565143c86a7a9cd86450fa99cad6a37a79ba50f9db02",
    ),
    Artifact(
        MODEL_REPOSITORY,
        MODEL_REVISION,
        f"{MODEL_PREFIX}/mimi_decoder_int8.onnx",
        "mimi_decoder_int8.onnx",
        22_684_077,
        "691f89f074585c828914cecd5396e30e0e2a14dbfa4890bd1b5806d303daeb4e",
    ),
    Artifact(
        MODEL_REPOSITORY,
        MODEL_REVISION,
        f"{MODEL_PREFIX}/mimi_encoder_int8.onnx",
        "mimi_encoder_int8.onnx",
        20_779_616,
        "37029c2653a2360e56dfe71140e4561104dd7e5410415156934d0ad4d153399d",
    ),
    Artifact(
        MODEL_REPOSITORY,
        MODEL_REVISION,
        f"{MODEL_PREFIX}/text_conditioner_int8.onnx",
        "text_conditioner_int8.onnx",
        16_388_384,
        "0e046165bd63f24f9f1a0256bc2ba5f5ace1c9e26a51546ec218edea73834a3f",
    ),
    Artifact(
        MODEL_REPOSITORY,
        MODEL_REVISION,
        f"{MODEL_PREFIX}/tokenizer.model",
        "tokenizer.model",
        60_995,
        "3aa51309c55f114771c156aaeb86f6fc325991364aa3c38af74aecf1cbd0fade",
    ),
    Artifact(
        MODEL_REPOSITORY,
        MODEL_REVISION,
        f"{MODEL_PREFIX}/bos_before_voice.npy",
        "bos_before_voice.npy",
        4_224,
        "9396378d581d63554cc30f2861e5d5b825650ff3dd3594a9ddc73d18df0973f1",
    ),
    Artifact(
        VOICE_REPOSITORY,
        VOICE_REVISION,
        VOICE_PATH,
        "reference_voice.wav",
        960_078,
        "f175b5bee6d89f13b1bb10e2a4de7ad8e4f0df59438c2b96ce4bcfc4bfe03dd6",
    ),
)

GENERATED_FILES = (
    "vocab.json",
    "token_scores.json",
    "mimi_encoder_bos_int8.onnx",
    "manifest.json",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _valid(path: Path, artifact: Artifact) -> bool:
    return (
        path.is_file()
        and path.stat().st_size == artifact.size
        and _sha256(path) == artifact.sha256
    )


def _hf_token() -> str | None:
    token = os.environ.get("HF_TOKEN")
    if token:
        return token
    path = Path.home() / ".cache" / "huggingface" / "token"
    return path.read_text().strip() if path.is_file() else None


def _download(artifact: Artifact, output_dir: Path, force: bool) -> None:
    destination = output_dir / artifact.local_name
    if not force and _valid(destination, artifact):
        print(f"ok       {artifact.local_name}")
        return

    temporary = destination.with_suffix(f"{destination.suffix}.part")
    temporary.unlink(missing_ok=True)
    print(f"baixando {artifact.local_name} ({artifact.size / 1_000_000:.1f} MB)")
    headers = {"User-Agent": "tcc-ela-pocket-tts-assets/1.0"}
    token = _hf_token()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(artifact.url, headers=headers)
    try:
        with urllib.request.urlopen(request) as response, temporary.open("wb") as target:
            while chunk := response.read(1024 * 1024):
                target.write(chunk)
    except urllib.error.HTTPError as error:
        temporary.unlink(missing_ok=True)
        if error.code in (401, 403):
            raise RuntimeError(
                f"acesso negado a {artifact.repository}: aceite os termos em "
                f"https://huggingface.co/{artifact.repository} e defina HF_TOKEN "
                "ou rode `hf auth login`"
            ) from error
        raise
    except Exception:
        temporary.unlink(missing_ok=True)
        raise

    if not _valid(temporary, artifact):
        temporary.unlink(missing_ok=True)
        raise RuntimeError(f"tamanho ou SHA-256 inválido para {artifact.local_name}")
    temporary.replace(destination)


def _write_json(path: Path, value: object) -> None:
    temporary = path.with_suffix(f"{path.suffix}.part")
    temporary.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(path)


def _convert_tokenizer(output_dir: Path) -> None:
    try:
        import sentencepiece as spm
    except ImportError as error:
        raise RuntimeError(
            "sentencepiece não está instalado; execute "
            "`python3 -m pip install -r tool/requirements-pocket-tts.txt`"
        ) from error

    tokenizer = spm.SentencePieceProcessor(
        model_file=str(output_dir / "tokenizer.model")
    )
    vocab = {}
    scores = {}
    for token_id in range(tokenizer.get_piece_size()):
        token = tokenizer.id_to_piece(token_id)
        vocab[token] = token_id
        scores[token] = tokenizer.get_score(token_id)

    _write_json(output_dir / "vocab.json", vocab)
    _write_json(output_dir / "token_scores.json", scores)


def _embed_bos_in_encoder(output_dir: Path) -> None:
    try:
        import numpy as np
        import onnx
        from onnx import helper, numpy_helper
    except ImportError as error:
        raise RuntimeError(
            "onnx não está instalado; execute "
            "`python3 -m pip install -r tool/requirements-pocket-tts.txt`"
        ) from error

    bos = np.load(output_dir / "bos_before_voice.npy").astype(np.float32)
    model = onnx.load(output_dir / "mimi_encoder_int8.onnx")
    graph = model.graph
    latents = graph.output[0].name
    for node in graph.node:
        node.output[:] = [
            "latents_without_bos" if name == latents else name
            for name in node.output
        ]
    graph.initializer.append(
        numpy_helper.from_array(bos.reshape(1, -1, bos.shape[-1]), "bos_before_voice")
    )
    graph.node.append(
        helper.make_node(
            "Concat", ["bos_before_voice", "latents_without_bos"], [latents], axis=1
        )
    )
    onnx.checker.check_model(model)
    destination = output_dir / "mimi_encoder_bos_int8.onnx"
    temporary = destination.with_suffix(".onnx.part")
    onnx.save(model, temporary)
    temporary.replace(destination)


def _write_manifest(output_dir: Path) -> None:
    sources = {
        artifact.local_name: {
            "repository": artifact.repository,
            "revision": artifact.revision,
            "path": artifact.remote_path,
            "size": artifact.size,
            "sha256": artifact.sha256,
        }
        for artifact in ARTIFACTS
    }
    generated = {
        filename: {
            "size": (output_dir / filename).stat().st_size,
            "sha256": _sha256(output_dir / filename),
        }
        for filename in GENERATED_FILES
        if filename != "manifest.json"
    }
    _write_json(
        output_dir / "manifest.json",
        {
            "schema": 1,
            "runtime": "sherpa_onnx 1.13.8",
            "language": "portuguese",
            "precision": "int8",
            "sources": sources,
            "generated": generated,
        },
    )


def _verify(output_dir: Path) -> None:
    problems = []
    for artifact in ARTIFACTS:
        if not _valid(output_dir / artifact.local_name, artifact):
            problems.append(artifact.local_name)
    for filename in GENERATED_FILES:
        if not (output_dir / filename).is_file():
            problems.append(filename)
    if problems:
        raise RuntimeError("arquivos ausentes ou inválidos: " + ", ".join(problems))
    print(f"bundle verificado em {output_dir}")


def main() -> int:
    project_root = Path(__file__).resolve().parent.parent
    default_output = project_root / "assets" / "models" / "pocket_tts_pt"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=default_output)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()

    output_dir = args.output.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    if args.verify_only:
        _verify(output_dir)
        return 0

    for artifact in ARTIFACTS:
        _download(artifact, output_dir, args.force)
    _convert_tokenizer(output_dir)
    _embed_bos_in_encoder(output_dir)
    _write_manifest(output_dir)
    _verify(output_dir)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, RuntimeError) as error:
        print(f"erro: {error}", file=sys.stderr)
        raise SystemExit(1)
