"""Gera tool/iterations-table.csv com uma linha por sessão de sessoes/T1, sessoes/T2 e sessoes/T3.

Uso: python tool/gerar_tabela.py

A iteração é a ordem da sessão dentro do teste, pela hora do arquivo
(session_AAAAMMDD_HHMMSS.json). As colunas são as que o notebook
tool/grafico_iteracoes.ipynb lê.

Além do resumo que o app grava (summary), a navegação é refeita a partir do log
(events), com as regras da tela, para obter o que o app não calcula: o mínimo
de comandos até cada tecla acionada, as reversões (↑ seguido de ↓ etc.) e as
entradas na barra de sugestões sem aceitar nada. A frase e os campos são
comparados com sessoes/teste_ground_truth/TN.json.
"""
import json
from collections import deque
from pathlib import Path
from statistics import median

import pandas as pd

RAIZ = Path(__file__).resolve().parent.parent
SESSOES = RAIZ / 'sessoes'
SAIDA = Path(__file__).resolve().parent / 'iterations-table.csv'
TESTES = ['T1', 'T2', 'T3']
TECLADO = [list('QWERTYUIOP'), list('ASDFGHJKL'), list('ZXCVBNM'),
           ['FALAR', 'ESPAÇO', 'APAGAR', 'LIMPAR']]
OPOSTO = {'up': 'down', 'down': 'up', 'left': 'right', 'right': 'left'}
CAMPOS_DE_TEMPO = {'durationSeconds', 'startSeconds', 'wordsPerMinute', 'secondsPerInteraction'}


def mover(pos, comando):
    linha, coluna = pos
    linha += {'up': -1, 'down': 1}.get(comando, 0)
    coluna += {'left': -1, 'right': 1}.get(comando, 0)
    linha = max(0, min(linha, len(TECLADO) - 1))
    return linha, max(0, min(coluna, len(TECLADO[linha]) - 1))


def menor_caminho(origem, alvo):
    """Busca em largura no teclado, com a coluna limitada ao trocar de linha."""
    distancia, fila = {origem: 0}, deque([origem])
    while fila:
        pos = fila.popleft()
        if pos == alvo:
            return distancia[pos]
        for comando in OPOSTO:
            vizinho = mover(pos, comando)
            if vizinho not in distancia:
                distancia[vizinho] = distancia[pos] + 1
                fila.append(vizinho)


def refazer_navegacao(eventos):
    pos, barra, sugestoes = (0, 0), None, []
    inicio, minimo, entradas_barra, aceitas = (0, 0), 0, 0, 0
    comandos = [e for e in eventos if e['type'] == 'command']
    for e in eventos:
        if e['type'] == 'suggestions':
            sugestoes = e['suggestions']
        elif e['type'] == 'command' and e['command'] != 'select':
            cmd = e['command']
            if barra is not None:
                if cmd == 'down':
                    barra = None
                elif cmd in ('left', 'right'):
                    barra = max(0, min(barra + (1 if cmd == 'right' else -1), len(sugestoes) - 1))
            elif cmd == 'up' and pos[0] == 0 and sugestoes:
                barra = 0
                entradas_barra += 1
            else:
                pos = mover(pos, cmd)
        elif e['type'] == 'key':
            alvo = (e['row'], e['column'])
            minimo += menor_caminho(inicio, alvo) + 1
            pos, barra, inicio = alvo, None, alvo
        elif e['type'] == 'acceptance':
            # Da linha atual até a barra, depois até a sugestão, e OK.
            minimo += inicio[0] + 1 + e['rank'] + 1
            aceitas += 1
            barra, inicio = None, pos
    nomes = [c['command'] for c in comandos]
    intervalos = [(b['t'] - a['t']) / 1000 for a, b in zip(comandos, comandos[1:])]
    return {
        'minimo': minimo,
        'reversoes': sum(OPOSTO.get(a) == b for a, b in zip(nomes, nomes[1:])),
        # Toda aceitação também entra na barra; o que sobra foi sem querer.
        'barra_sem_querer': max(0, entradas_barra - aceitas),
        'mediana': median(intervalos) if intervalos else None,
        'pausas_5s': sum(i > 5 for i in intervalos),
    }


def achatar(d, prefixo=''):
    """Campos de contagem de uma frase, sem os de tempo nem gaze/touch."""
    saida = {}
    for k, v in d.items():
        if k in CAMPOS_DE_TEMPO or (prefixo == 'interactions.' and k in ('gaze', 'touch')):
            continue
        if isinstance(v, dict):
            saida.update(achatar(v, f'{prefixo}{k}.'))
        elif k == 'words' and isinstance(v, list):
            for i, palavra in enumerate(v):
                saida.update(achatar(palavra, f'words[{i}].'))
        else:
            saida[prefixo + k] = v
    return saida


def modo(interacoes):
    olhar, toque = interacoes.get('gaze', 0), interacoes.get('touch', 0)
    if olhar and not toque:
        return 'olhar'
    if toque and not olhar:
        return 'toque/direcional'
    return f'misto ({olhar} olhar, {toque} toque)'


def linha_da_sessao(teste, iteracao, arquivo, esperado):
    dados = json.loads(arquivo.read_text())
    s, frases = dados['summary'], dados['phrases']
    nav = refazer_navegacao(dados['events'])
    uma_frase = len(frases) == 1
    if uma_frase:
        real, esp = achatar(frases[0]), achatar(esperado)
        campos_ok = f'{sum(real.get(k) == v for k, v in esp.items())}/{len(esp)}'
    else:
        campos_ok = '–'
    data = arquivo.stem.split('_')  # session, AAAAMMDD, HHMMSS
    total = s['interactions']['total']
    return {
        'teste': teste,
        'iteracao': f'{iteracao:02d}',
        'data': f'{data[1][6:8]}/{data[1][4:6]} {data[2][:2]}:{data[2][2:4]}',
        'modo': modo(s['interactions']),
        'frase': ' / '.join(f['text'] for f in frases),
        'frase_ok': uma_frase and frases[0]['text'] == esperado['text'],
        'frases': s['phrases'],
        'duracao_s': s['durationSeconds'],
        'comandos': total,
        'linha_base': s['interactions']['baseline'],
        'minimo_navegacao': nav['minimo'],
        'eficiencia': nav['minimo'] / total if total else None,
        'kspc': s['kspc']['interactions'],
        'economia': s['keystrokeSavings']['interactions'],
        'selecoes': s['interactions']['selections'],
        'apagados': s['errors']['erasedCharacters'],
        'taxa_erros_corrigidos': s['errors']['correctedErrorRate'],
        'sugestoes_aceitas': s['prediction']['acceptances'],
        'wpm': s['wordsPerMinute'],
        's_por_comando': s['secondsPerInteraction'],
        'mediana_s_comando': nav['mediana'],
        'reversoes': nav['reversoes'],
        'entradas_barra_sem_querer': nav['barra_sem_querer'],
        'pausas_5s': nav['pausas_5s'],
        'campos_ok': campos_ok,
        'arquivo': arquivo.name,
    }


def main():
    linhas = []
    for teste in TESTES:
        esperado = json.loads((SESSOES / 'teste_ground_truth' / f'{teste}.json').read_text())['phrases'][0]
        sessoes = sorted((SESSOES / teste).glob('session_*.json'))
        for iteracao, arquivo in enumerate(sessoes, start=1):
            linhas.append(linha_da_sessao(teste, iteracao, arquivo, esperado))
    if not linhas:
        raise SystemExit('Nenhuma sessão em sessoes/T1, sessoes/T2 ou sessoes/T3.')

    tabela = pd.DataFrame(linhas)
    tabela.to_csv(SAIDA, index=False)
    with pd.option_context('display.width', 200, 'display.max_columns', None):
        print(tabela[['teste', 'iteracao', 'data', 'modo', 'frase', 'duracao_s', 'comandos',
                      'eficiencia', 'economia', 'wpm', 'campos_ok']].to_string(index=False))
    print(f'\nGravado: {SAIDA.relative_to(RAIZ)} ({len(tabela)} sessões)')


if __name__ == '__main__':
    main()
