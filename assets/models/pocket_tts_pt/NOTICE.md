# Pocket TTS — avisos de terceiros

Este diretório é preenchido por `tool/fetch_pocket_tts_model.py`.

## Modelo ONNX em português

- Obra: Pocket TTS, da Kyutai
- Conversão ONNX: KevinAHM
- Fonte: <https://huggingface.co/KevinAHM/pocket-tts-onnx>
- Revisão: `58a6d00cf13d239b6748cb0769f35c580a8f606c`
- Licença dos arquivos ONNX: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)

Os modelos são cópias quantizadas para INT8. O encoder Mimi foi modificado
para concatenar o embedding `bos_before_voice.npy` do mesmo bundle antes das
latentes da voz, passo que o runtime não executa. Essas modificações são
indicadas aqui para atender à atribuição da licença.

## Voz de referência

- Voz: `rafael` (pt), do catálogo de vozes predefinidas do Pocket TTS
- Arquivo: `g-Vi8PgmSY0-enhanced-v2.wav`
- Fonte: <https://huggingface.co/kyutai/pocket-tts/blob/64ab7d24c479d736a83b8cc666c4a776fca30fda/g-Vi8PgmSY0-enhanced-v2.wav>
- Catálogo: <https://github.com/kyutai-labs/pocket-tts#readme>
- Licença do repositório: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/)

A gravação é usada apenas como condicionamento de timbre. O modelo português
continua responsável pelo texto e pela pronúncia. A voz pode ser substituída
por outra amostra WAV cuja redistribuição e clonagem tenham sido autorizadas.

## Runtime

- Obra: sherpa-onnx, versão 1.13.8
- Fonte: <https://github.com/k2-fsa/sherpa-onnx>
- Licença: [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0)

O uso de clonagem de voz exige consentimento explícito do titular e deve
respeitar as leis aplicáveis e as condições do Pocket TTS.
