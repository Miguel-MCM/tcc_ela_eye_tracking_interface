#!/usr/bin/env python3
"""Gera a tabela de estatísticas dos testes T1, T2 e T3.

Uso:
    python3 tool/gerar_tabela.py PASTA_T1 PASTA_T2 PASTA_T3 \\
        [--esperados PASTA] [--saida PASTA]

Cada pasta contém as sessões de um teste (session_*.json ou NN_session_*.json);
uma pasta vazia é aceita, para um teste ainda não executado. Grava em --saida
(padrão: pasta atual):
- tabela.md: uma tabela por iteração e um resumo por teste;
- tabela.csv: as mesmas linhas por iteração, lida por grafico_iteracoes.ipynb.

Além das métricas que o app já calcula (summary do JSON), refaz a navegação a
partir do log (events), com as mesmas regras da tela, para obter o que o app
não calcula: eficiência de navegação (menor caminho ÷ comandos usados),
reversões imediatas (↑ seguido de ↓ etc.) e entradas na barra de sugestões
sem aceitar nada. Com --esperados (pasta com esperado_T1.json etc.), também
confere a frase e quantos campos batem com o esperado (fora os de tempo). Só
usa a biblioteca padrão.
"""
import argparse
import csv
import json
import re
from collections import deque
from pathlib import Path
from statistics import mean, median

TESTS = ['T1', 'T2', 'T3']
ROWS = [list('QWERTYUIOP'), list('ASDFGHJKL'), list('ZXCVBNM'),
        ['FALAR', 'ESPAÇO', 'APAGAR', 'LIMPAR']]
OPPOSITE = {'up': 'down', 'down': 'up', 'left': 'right', 'right': 'left'}
TIME_FIELDS = {'durationSeconds', 'startSeconds', 'wordsPerMinute', 'secondsPerInteraction'}


# ---------- navegação (mesmas regras de CommunicatorScreen) ----------

def move(pos, cmd):
    r, c = pos
    if cmd == 'up':
        r = max(r - 1, 0)
    elif cmd == 'down':
        r = min(r + 1, len(ROWS) - 1)
    elif cmd == 'left':
        c -= 1
    elif cmd == 'right':
        c += 1
    return r, max(0, min(c, len(ROWS[r]) - 1))


def shortest(a, b):
    seen, queue = {a: 0}, deque([a])
    while queue:
        p = queue.popleft()
        if p == b:
            return seen[p]
        for cmd in OPPOSITE:
            n = move(p, cmd)
            if n not in seen:
                seen[n] = seen[p] + 1
                queue.append(n)
    raise ValueError(f'sem caminho de {a} para {b}')


def replay(events):
    """Menor número de comandos para cada acionamento, reversões e entradas na barra."""
    pos, bar, suggestions = (0, 0), None, []
    start, minimum, bar_entries, accepted_from_bar = (0, 0), 0, 0, 0
    commands = []
    for e in events:
        kind = e['type']
        if kind == 'suggestions':
            suggestions = e['suggestions']
        elif kind == 'command':
            cmd = e['command']
            commands.append(cmd)
            if cmd == 'select':
                continue
            if bar is not None:
                if cmd == 'down':
                    bar = None
                elif cmd in ('left', 'right'):
                    bar = max(0, min(bar + (1 if cmd == 'right' else -1), len(suggestions) - 1))
            elif cmd == 'up' and pos[0] == 0 and suggestions:
                bar = 0
                bar_entries += 1
            else:
                pos = move(pos, cmd)
        elif kind == 'key':
            target = (e['row'], e['column'])
            minimum += shortest(start, target) + 1
            pos, bar, start = target, None, target
        elif kind == 'acceptance':
            # Da linha atual até a barra, depois até a posição da sugestão, e OK.
            minimum += start[0] + 1 + e['rank'] + 1
            accepted_from_bar += 1
            bar, start = None, pos
    reversals = sum(1 for a, b in zip(commands, commands[1:]) if OPPOSITE.get(a) == b)
    gaps = [(b['t'] - a['t']) / 1000 for a, b in
            zip([e for e in events if e['type'] == 'command'],
                [e for e in events if e['type'] == 'command'][1:])]
    return {
        'minimum': minimum,
        'reversals': reversals,
        # Cada aceitação também entrou na barra; o que sobra foi sem querer.
        'idle_bar_entries': max(0, bar_entries - accepted_from_bar),
        'median_gap': median(gaps) if gaps else None,
        'pauses_over_5s': sum(g > 5 for g in gaps),
    }


# ---------- comparação com o esperado ----------

def flatten(d, prefix=''):
    out = {}
    for k, v in d.items():
        if k in TIME_FIELDS or (prefix == 'interactions.' and k in ('gaze', 'touch')):
            continue
        key = prefix + k
        if isinstance(v, dict):
            out.update(flatten(v, key + '.'))
        elif k == 'words' and isinstance(v, list):
            for i, w in enumerate(v):
                out.update(flatten(w, f'words[{i}].'))
        else:
            out[key] = v
    return out


def matching_fields(phrase, expected):
    real, exp = flatten(phrase), flatten(expected)
    return sum(real.get(k) == v for k, v in exp.items()), len(exp)


# ---------- leitura das iterações ----------

def mode(inter):
    gaze, touch = inter.get('gaze', 0), inter.get('touch', 0)
    if gaze and not touch:
        return 'olhar'
    if touch and not gaze:
        return 'toque/direcional'
    return f'misto ({gaze} olhar, {touch} toque)'


def iteration_rows(folders, expected_dir=None):
    rows = []
    for test, folder in zip(TESTS, folders):
        expected_file = expected_dir / f'esperado_{test}.json' if expected_dir else None
        expected = (json.loads(expected_file.read_text())['phrases'][0]
                    if expected_file and expected_file.exists() else None)
        for index, path in enumerate(sorted(folder.glob('*session_*.json')), start=1):
            data = json.loads(path.read_text())
            s = data['summary']
            phrases = data['phrases']
            nav = replay(data['events'])
            match = matching_fields(phrases[0], expected) if expected and len(phrases) == 1 else None
            number = re.match(r'(\d+)_', path.name)
            stamp = re.search(r'session_(\d{8})_(\d{6})', path.name)
            total = s['interactions']['total']
            rows.append({
                'teste': test,
                'iteracao': number.group(1) if number else f'{index:02d}',
                'data': (f'{stamp.group(1)[6:8]}/{stamp.group(1)[4:6]} '
                         f'{stamp.group(2)[:2]}:{stamp.group(2)[2:4]}') if stamp else '',
                'modo': mode(s['interactions']),
                'frase': ' / '.join(p['text'] for p in phrases),
                'frase_ok': None if expected is None else len(phrases) == 1 and phrases[0]['text'] == expected['text'],
                'frases': s['phrases'],
                'duracao_s': s['durationSeconds'],
                'comandos': total,
                'linha_base': s['interactions']['baseline'],
                'minimo_navegacao': nav['minimum'],
                'eficiencia': nav['minimum'] / total if total else None,
                'kspc': s['kspc']['interactions'],
                'economia': s['keystrokeSavings']['interactions'],
                'selecoes': s['interactions']['selections'],
                'apagados': s['errors']['erasedCharacters'],
                'taxa_erros_corrigidos': s['errors']['correctedErrorRate'],
                'sugestoes_aceitas': s['prediction']['acceptances'],
                'wpm': s['wordsPerMinute'],
                's_por_comando': s['secondsPerInteraction'],
                'mediana_s_comando': nav['median_gap'],
                'reversoes': nav['reversals'],
                'entradas_barra_sem_querer': nav['idle_bar_entries'],
                'pausas_5s': nav['pauses_over_5s'],
                'campos_ok': f'{match[0]}/{match[1]}' if match else '–',
                'arquivo': path.name,
            })
    return rows


# ---------- formatação ----------

def num(v, digits=2):
    if v is None:
        return '–'
    if isinstance(v, int):
        return str(v)
    return f'{v:.{digits}f}'.replace('.', ',')


def pct(v):
    return '–' if v is None else f'{v * 100:.1f}%'.replace('.', ',')


def summary_rows(rows):
    out = []
    for test in TESTS:
        it = [r for r in rows if r['teste'] == test]
        if not it:
            out.append((test, 0, *(['–'] * 8)))
            continue

        def stat(key, fmt=num):
            values = [r[key] for r in it if r[key] is not None]
            if not values:
                return '–'
            if len(values) == 1:
                return fmt(values[0])
            return f'{fmt(mean(values))} ({fmt(min(values))}–{fmt(max(values))})'

        out.append((test, len(it),
                    f"{sum(r['frase_ok'] is True for r in it)}/{len(it)}" if it[0]['frase_ok'] is not None else '–',
                    stat('duracao_s', lambda v: num(v, 1)),
                    stat('comandos', lambda v: num(v, 1) if isinstance(v, float) else str(v)),
                    stat('eficiencia', pct),
                    stat('economia', pct),
                    stat('apagados', lambda v: num(v, 1) if isinstance(v, float) else str(v)),
                    stat('wpm', lambda v: num(v, 3)),
                    stat('mediana_s_comando')))
    return out


def markdown(rows):
    lines = ['# Tabela dos testes com usuários sem ELA', '',
             'Gerada por `tool/gerar_tabela.py`. **Não editar à mão:** rode o script de novo.', '',
             '## Resumo por teste', '',
             'Média (mínimo–máximo) das iterações.', '',
             '| Teste | Iterações | Frase certa | Duração (s) | Comandos | Eficiência | Economia | Apagados | WPM | Mediana s/comando |',
             '|---|---|---|---|---|---|---|---|---|---|']
    for r in summary_rows(rows):
        lines.append('| ' + ' | '.join(str(x) for x in r) + ' |')
    lines += ['', '## Por iteração', '',
              '| Teste | # | Data | Modo | Frase | Duração (s) | Comandos | Mínimo nav. | Linha de base | Eficiência | KSPC | Economia | Apagados | Taxa erros corr. | Sugestões aceitas | WPM | Mediana s/cmd | Reversões | Barra sem querer | Pausas > 5 s | Campos = esperado |',
              '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|']
    for r in rows:
        frase = r['frase'] + (' ⚠️' if r['frase_ok'] is False else '')
        lines.append('| ' + ' | '.join([
            r['teste'], r['iteracao'], r['data'], r['modo'], frase, num(r['duracao_s'], 1),
            str(r['comandos']), str(r['minimo_navegacao']), str(r['linha_base']), pct(r['eficiencia']),
            num(r['kspc']), pct(r['economia']), str(r['apagados']), pct(r['taxa_erros_corrigidos']),
            str(r['sugestoes_aceitas']), num(r['wpm'], 3), num(r['mediana_s_comando']),
            str(r['reversoes']), str(r['entradas_barra_sem_querer']), str(r['pausas_5s']), r['campos_ok'],
        ]) + ' |')
    lines += ['', '## Legenda', '',
              '- **Mínimo nav.:** soma dos menores caminhos até cada tecla ou sugestão **de fato acionada** (inclui os erros e as correções). **Linha de base:** mínimo para digitar a frase **final** letra a letra, sem sugestões (calculada pelo app).',
              '- **Eficiência** = mínimo nav. ÷ comandos (100% = nenhum comando desperdiçado navegando). **Economia** = 1 − comandos ÷ linha de base (calculada pelo app).',
              '- **Reversões:** um comando seguido logo pelo oposto (↑ ↓, → ←). **Barra sem querer:** entradas na barra de sugestões sem aceitar nada.',
              '- **Campos = esperado:** campos de contagem iguais aos de `esperado_TN.json` (fora os de tempo). Pelo olhar, só batem todos se nenhum comando sair a mais.',
              '- ⚠️ na frase: o texto falado não é a frase do teste.']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description='Gera tabela.md e tabela.csv a partir das sessões dos testes T1, T2 e T3.')
    for test in TESTS:
        parser.add_argument(test.lower(), type=Path, metavar=f'PASTA_{test}', help=f'pasta com as sessões do teste {test}')
    parser.add_argument('--esperados', type=Path, metavar='PASTA', help='pasta com esperado_T1.json, esperado_T2.json e esperado_T3.json')
    parser.add_argument('--saida', type=Path, default=Path('.'), metavar='PASTA', help='onde gravar as tabelas (padrão: pasta atual)')
    args = parser.parse_args()

    folders = [getattr(args, test.lower()) for test in TESTS]
    for folder in [*folders, *([args.esperados] if args.esperados else [])]:
        if not folder.is_dir():
            parser.error(f'pasta não encontrada: {folder}')

    rows = iteration_rows(folders, args.esperados)
    if not rows:
        parser.error('nenhuma sessão encontrada nas pastas informadas')
    args.saida.mkdir(parents=True, exist_ok=True)
    (args.saida / 'tabela.md').write_text(markdown(rows))
    with open(args.saida / 'tabela.csv', 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    print(markdown(rows))
    print(f'Gravados: {args.saida / "tabela.md"} e {args.saida / "tabela.csv"} ({len(rows)} iterações)')


if __name__ == '__main__':
    main()
