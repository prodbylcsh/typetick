"""Shared machine layout. The Swift app reads the same numbers from the
manifests, so keep any change here in sync through the manifests only."""

CARRIAGE_ANCHOR = [0.0, 0.140, -0.070]       # platen axis center
BASKET = dict(center=[0.0, 0.075, -0.030], radius=0.070, arcDegrees=150.0, restTiltDegrees=26.0)
SPOOL_LEFT = [-0.125, 0.110, -0.028]
SPOOL_RIGHT = [0.125, 0.110, -0.028]
CORRECTION_LEFT = [-0.078, 0.104, -0.040]
CORRECTION_RIGHT = [0.078, 0.104, -0.040]
BELL = [-0.160, 0.096, -0.112]
RECORDER = [0.330, 0.0, 0.020]

KEYBOARD = dict(
    frontZ=0.150,      # z of the front (ZXCV) row key tops
    rowPitchZ=0.0215,
    frontY=0.050,      # key top height of the front row
    rowRiseY=0.0095,
    keyPitchX=0.0205,
    rowStaggerX=[0.0, -0.0052, -0.0102, -0.0154],
    spaceZ=0.176,
    spaceY=0.040,
)


def chassis_mechanics(**over):
    m = dict(
        anchors=dict(
            carriage=list(CARRIAGE_ANCHOR),
            spoolLeft=list(SPOOL_LEFT), spoolRight=list(SPOOL_RIGHT),
            correctionLeft=list(CORRECTION_LEFT), correctionRight=list(CORRECTION_RIGHT),
            bell=list(BELL), recorder=list(RECORDER),
        ),
        basket=dict(BASKET),
        keyboard=dict(KEYBOARD),
        shiftType="segment",         # segment | carriage
        shiftTravel=0.0055,
        frameResonance=0.5,          # 0 = dead plastic box, 1 = ringing open steel frame
    )
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(m.get(k), dict):
            m[k] = {**m[k], **v}
        else:
            m[k] = v
    return m
