#!/usr/bin/env python3
"""Gera figura da detecção do Face Mesh (topologia 468 pontos do ML Kit) para o TCC.

Desenha a malha de 468 pontos sobre o rosto e destaca explicitamente os 4 pontos
utilizados pelo sistema (`kEyeCorners` em `lib/gaze/gaze_tracker.dart`):
  - Olho direito: 33 (canto externo, c_A) e 133 (canto interno, c_B)
  - Olho esquerdo: 362 (canto interno, c_A) e 263 (canto externo, c_B)
além do ponto médio m = (c_A + c_B) / 2 e do quadrado de recorte 1,6x (cropTransform).

Uso:
  ../eye_tracker/.venv/bin/python tool/render_facemesh.py [imagem] [-o saida.png]
"""

from __future__ import annotations

import argparse
import json
import math
import urllib.request
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks.python.vision import FaceLandmarksConnections

ROOT = Path(__file__).resolve().parents[1]
CROP_PARAMS_PATH = ROOT / "assets" / "models" / "crop_params.json"
DEFAULT_MODEL = ROOT.parent / "eye_tracker" / "models" / "face_landmarker.task"
DEFAULT_IMAGE = ROOT.parent / "selfies" / "WhatsApp Image 2026-05-03 at 13.03.54.jpeg"
DEFAULT_OUTPUT = ROOT.parent / "Apresentacao-TCC" / "figuras" / "mlkit_facemesh.png"
MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/face_landmarker/"
    "face_landmarker/float16/1/face_landmarker.task"
)

# Mesmos índices de `kEyeCorners` em `lib/gaze/gaze_tracker.dart`.
EYE_CORNERS: dict[str, tuple[int, int]] = {
    "right": (33, 133),
    "left": (362, 263),
}

# Cores BGR
COLOR_MESH = (220, 200, 140)      # malha de 468 pontos
COLOR_EYE_RING = (255, 230, 150)  # contorno das pálpebras
COLOR_CROP_BOX = (255, 195, 50)   # recorte alinhado 1,6x (128x128)
COLOR_AXIS = (0, 215, 255)        # vetor c_A -> c_B (largura e roll)
COLOR_CORNER = (60, 230, 70)      # cantos usados pelo sistema (33, 133, 362, 263)
COLOR_MID = (50, 90, 255)         # centro m = (c_A + c_B) / 2


def ensure_model(path: Path) -> Path:
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(MODEL_URL, path)
    return path


def detect_landmarks_468(image_bgr: np.ndarray, model_path: Path) -> np.ndarray:
    """Retorna os 468 pontos (x, y em px) da topologia canônica do ML Kit Face Mesh."""
    vision = mp.tasks.vision
    options = vision.FaceLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_path=str(ensure_model(model_path))),
        running_mode=vision.RunningMode.IMAGE,
        num_faces=1,
    )
    with vision.FaceLandmarker.create_from_options(options) as landmarker:
        rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
        result = landmarker.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
    if not result.face_landmarks:
        raise SystemExit("Nenhum rosto detectado na imagem.")
    h, w = image_bgr.shape[:2]
    # O FaceLandmarker devolve 478 pontos (468 do Face Mesh + 10 de íris).
    # O ML Kit Face Mesh possui exatamente os 468 primeiros (0..467).
    return np.array([(p.x * w, p.y * h) for p in result.face_landmarks[0][:468]], dtype=np.float64)


def crop_face_region(image: np.ndarray, pts: np.ndarray, target_w: int = 960) -> tuple[np.ndarray, np.ndarray]:
    """Recorta o rosto e redimensiona para largura fixa, ajustando as coordenadas."""
    h, w = image.shape[:2]
    x0, y0 = pts.min(axis=0)
    x1, y1 = pts.max(axis=0)
    span = max(x1 - x0, (y1 - y0) * 0.92)
    cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0 - 0.03 * (y1 - y0)

    half_w = span * 0.62
    half_h = span * 0.50
    ix0, iy0 = max(0, int(round(cx - half_w))), max(0, int(round(cy - half_h)))
    ix1, iy1 = min(w, int(round(cx + half_w))), min(h, int(round(cy + half_h)))

    cropped = image[iy0:iy1, ix0:ix1].copy()
    shifted = pts - np.array([ix0, iy0], dtype=np.float64)
    scale = target_w / cropped.shape[1]
    target_h = int(round(cropped.shape[0] * scale))
    return cv2.resize(cropped, (target_w, target_h), interpolation=cv2.INTER_AREA), shifted * scale


def eye_crop_quad(a: np.ndarray, b: np.ndarray, crop_ratio: float, align_roll: bool) -> np.ndarray:
    """Vértices no frame do quadrado de recorte 128x128 (`eye_crop.dart`)."""
    mid = (a + b) / 2.0
    d = b - a
    side = crop_ratio * float(np.linalg.norm(d))
    angle = math.atan2(d[1], d[0]) if align_roll else 0.0
    c, s = math.cos(angle), math.sin(angle)
    rot = np.array([[c, -s], [s, c]])
    half = side / 2.0
    corners = np.array([[-half, -half], [half, -half], [half, half], [-half, half]])
    return (corners @ rot.T + mid).astype(np.int32)


def draw_mesh_468(canvas: np.ndarray, pts: np.ndarray, mesh_alpha: float = 0.30) -> None:
    overlay = canvas.copy()
    for conn in FaceLandmarksConnections.FACE_LANDMARKS_TESSELATION:
        if conn.start < 468 and conn.end < 468:
            p0 = tuple(pts[conn.start].round().astype(int))
            p1 = tuple(pts[conn.end].round().astype(int))
            cv2.line(overlay, p0, p1, COLOR_MESH, 1, cv2.LINE_AA)
    for ring in (FaceLandmarksConnections.FACE_LANDMARKS_RIGHT_EYE, FaceLandmarksConnections.FACE_LANDMARKS_LEFT_EYE):
        for conn in ring:
            p0 = tuple(pts[conn.start].round().astype(int))
            p1 = tuple(pts[conn.end].round().astype(int))
            cv2.line(overlay, p0, p1, COLOR_EYE_RING, 1, cv2.LINE_AA)
    for x, y in pts.round().astype(int):
        cv2.circle(overlay, (int(x), int(y)), 2, COLOR_MESH, -1, cv2.LINE_AA)
    cv2.addWeighted(overlay, mesh_alpha, canvas, 1.0 - mesh_alpha, 0, dst=canvas)


def draw_callout(
    canvas: np.ndarray,
    point: np.ndarray,
    offset: tuple[int, int],
    text: str,
    accent: tuple[int, int, int],
    scale: float = 0.56,
) -> None:
    font = cv2.FONT_HERSHEY_SIMPLEX
    thick = 2
    (tw, th), base = cv2.getTextSize(text, font, scale, thick)
    px, py = int(round(point[0])), int(round(point[1]))
    tx, ty = px + offset[0], py + offset[1]

    pad_x, pad_y = 8, 6
    x0, y0 = tx - tw // 2 - pad_x, ty - th // 2 - pad_y
    x1, y1 = tx + tw // 2 + pad_x, ty + th // 2 + base + pad_y

    # Linha de chamada do ponto até a etiqueta
    anchor_y = y1 if offset[1] < 0 else y0
    cv2.line(canvas, (px, py), (tx, anchor_y), (20, 20, 20), 3, cv2.LINE_AA)
    cv2.line(canvas, (px, py), (tx, anchor_y), accent, 1, cv2.LINE_AA)

    sub = canvas[max(0, y0):min(canvas.shape[0], y1), max(0, x0):min(canvas.shape[1], x1)]
    if sub.size:
        sub[:] = (sub * 0.22 + np.array([18, 18, 18]) * 0.78).astype(np.uint8)
    cv2.rectangle(canvas, (x0, y0), (x1, y1), accent, 2, cv2.LINE_AA)
    cv2.putText(
        canvas,
        text,
        (tx - tw // 2, ty + th // 2),
        font,
        scale,
        (255, 255, 255),
        thick,
        cv2.LINE_AA,
    )


def annotate_system_points(
    canvas: np.ndarray,
    pts: np.ndarray,
    crop_ratio: float,
    align_roll: bool,
    with_callouts: bool = True,
    radius: int = 6,
) -> None:
    # Offsets das etiquetas para não se sobreporem nos dois olhos
    offsets = {
        33: (-44, -46),
        133: (36, -46),
        362: (-36, -46),
        263: (44, -46),
    }
    roles = {33: "cA", 133: "cB", 362: "cA", 263: "cB"}

    for idx_a, idx_b in EYE_CORNERS.values():
        a, b = pts[idx_a], pts[idx_b]
        mid = (a + b) / 2.0

        # 1. Quadrado do recorte 1,6x (cropTransform)
        quad = eye_crop_quad(a, b, crop_ratio, align_roll)
        cv2.polylines(canvas, [quad], True, (20, 20, 20), 4, cv2.LINE_AA)
        cv2.polylines(canvas, [quad], True, COLOR_CROP_BOX, 2, cv2.LINE_AA)

        # 2. Vetor c_A -> c_B (largura do olho e alinhamento de roll)
        pa = tuple(a.round().astype(int))
        pb = tuple(b.round().astype(int))
        pm = tuple(mid.round().astype(int))
        cv2.line(canvas, pa, pb, (20, 20, 20), 4, cv2.LINE_AA)
        cv2.line(canvas, pa, pb, COLOR_AXIS, 2, cv2.LINE_AA)

        # 3. Ponto médio m = (c_A + c_B) / 2 (referência do vetor pupila-canto)
        cv2.circle(canvas, pm, radius - 1, (20, 20, 20), -1, cv2.LINE_AA)
        cv2.circle(canvas, pm, max(3, radius - 2), COLOR_MID, -1, cv2.LINE_AA)
        if with_callouts:
            draw_callout(canvas, mid, (0, 44), "m", COLOR_MID)

        # 4. Cantos do olho no Face Mesh
        for idx, pt in ((idx_a, a), (idx_b, b)):
            p = tuple(pt.round().astype(int))
            cv2.circle(canvas, p, radius + 2, (20, 20, 20), -1, cv2.LINE_AA)
            cv2.circle(canvas, p, radius, COLOR_CORNER, -1, cv2.LINE_AA)
            if with_callouts:
                draw_callout(canvas, pt, offsets[idx], f"#{idx} ({roles[idx]})", COLOR_CORNER)


def make_eye_zoom_strip(
    base_face: np.ndarray,
    pts: np.ndarray,
    crop_ratio: float,
    align_roll: bool,
) -> np.ndarray:
    """Faixa com zoom na região dos olhos para leitura clara no projetor."""
    h, w = base_face.shape[:2]
    eye_pts = pts[[33, 133, 362, 263]]
    ex0, ey0 = eye_pts.min(axis=0)
    ex1, ey1 = eye_pts.max(axis=0)
    span_x = ex1 - ex0
    pad_x = span_x * 0.28
    pad_y_top = span_x * 0.22
    pad_y_bot = span_x * 0.16

    x0 = max(0, int(round(ex0 - pad_x)))
    x1 = min(w, int(round(ex1 + pad_x)))
    y0 = max(0, int(round(ey0 - pad_y_top)))
    y1 = min(h, int(round(ey1 + pad_y_bot)))

    roi = base_face[y0:y1, x0:x1].copy()
    scale = w / roi.shape[1]
    zoom_h = int(round(roi.shape[0] * scale))
    zoom = cv2.resize(roi, (w, zoom_h), interpolation=cv2.INTER_CUBIC)
    zoom_pts = (pts - np.array([x0, y0], dtype=np.float64)) * scale

    draw_mesh_468(zoom, zoom_pts, mesh_alpha=0.22)
    annotate_system_points(zoom, zoom_pts, crop_ratio, align_roll, with_callouts=True, radius=8)

    # Rótulo discreto do zoom
    cv2.rectangle(zoom, (0, 0), (w, zoom_h - 1), (80, 80, 80), 2)
    return zoom


def make_legend_bar(width: int) -> np.ndarray:
    bar_h = 54
    bar = np.full((bar_h, width, 3), 24, dtype=np.uint8)
    items = [
        (COLOR_MESH, "Malha 468 pts"),
        (COLOR_CORNER, "Cantos (#33, #133, #362, #263)"),
        (COLOR_MID, "Centro m"),
        (COLOR_AXIS, "Eixo cA->cB"),
        (COLOR_CROP_BOX, "Recorte 1,6x"),
    ]
    font = cv2.FONT_HERSHEY_SIMPLEX
    x = 18
    y = bar_h // 2 + 5
    for color, label in items:
        cv2.circle(bar, (x + 7, y - 6), 7, color, -1, cv2.LINE_AA)
        cv2.putText(bar, label, (x + 20, y), font, 0.48, (235, 235, 235), 1, cv2.LINE_AA)
        (tw, _), _ = cv2.getTextSize(label, font, 0.48, 1)
        x += tw + 42
    return bar


def render(image_bgr: np.ndarray, pts_full: np.ndarray, crop_params: dict) -> np.ndarray:
    crop_ratio = float(crop_params["crop_ratio"])
    align_roll = bool(crop_params["align_roll"])

    base_face, pts = crop_face_region(image_bgr, pts_full, target_w=960)
    top = base_face.copy()
    draw_mesh_468(top, pts, mesh_alpha=0.32)
    annotate_system_points(top, pts, crop_ratio, align_roll, with_callouts=False, radius=6)

    zoom = make_eye_zoom_strip(base_face, pts, crop_ratio, align_roll)
    legend = make_legend_bar(top.shape[1])
    return np.vstack([top, zoom, legend])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", nargs="?", type=Path, default=DEFAULT_IMAGE, help="Imagem de entrada")
    parser.add_argument("-o", "--output", type=Path, default=DEFAULT_OUTPUT, help="Imagem de saída")
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL, help="Caminho do face_landmarker.task")
    args = parser.parse_args()

    image = cv2.imread(str(args.image), cv2.IMREAD_COLOR)
    if image is None:
        raise SystemExit(f"Não foi possível abrir a imagem: {args.image}")

    crop_params = json.loads(CROP_PARAMS_PATH.read_text(encoding="utf-8"))
    pts = detect_landmarks_468(image, args.model)
    assert pts.shape == (468, 2), f"esperava 468 pontos do ML Kit, recebi {pts.shape}"
    for side, (ia, ib) in EYE_CORNERS.items():
        assert pts[ib, 0] > pts[ia, 0], f"vetor cA->cB invertido no olho {side}"
    out = render(image, pts, crop_params)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(args.output), out)

    print(f"Imagem gerada em: {args.output} ({out.shape[1]}x{out.shape[0]} px)")
    for side, (ia, ib) in EYE_CORNERS.items():
        a, b = pts[ia], pts[ib]
        mid = (a + b) / 2.0
        w = float(np.linalg.norm(b - a))
        print(
            f"  olho {side:5s}: cA=#{ia:<3d} ({a[0]:.1f}, {a[1]:.1f}) | "
            f"cB=#{ib:<3d} ({b[0]:.1f}, {b[1]:.1f}) | "
            f"m=({mid[0]:.1f}, {mid[1]:.1f}) | largura={w:.1f} px"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
