# Kokoro — avisos de terceiros

Este diretório é preenchido por `tool/fetch_kokoro_model.py`.

## Modelo Kokoro v1.0

- Obra: Kokoro-82M, de hexgrad
- Fonte: <https://huggingface.co/hexgrad/Kokoro-82M>
- Licença: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)

O modelo e a tabela de vozes vêm do pacote `kokoro-multi-lang-v1_0`
preparado pelo projeto sherpa-onnx
(<https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models>), sem
modificações. O app usa a voz `pf_dora` (português brasileiro).

## Dados do espeak-ng

- Obra: espeak-ng
- Fonte: <https://github.com/espeak-ng/espeak-ng>
- Licença: [GPL 3.0 ou posterior](https://www.gnu.org/licenses/gpl-3.0.html)

Apenas o subconjunto de `espeak-ng-data` necessário para `pt-br` é incluído
(tabelas fonéticas, `pt_dict` e as definições de idioma `pt` e `pt-BR`).

## Runtime

- Obra: sherpa-onnx, versão 1.13.8
- Fonte: <https://github.com/k2-fsa/sherpa-onnx>
- Licença: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)
