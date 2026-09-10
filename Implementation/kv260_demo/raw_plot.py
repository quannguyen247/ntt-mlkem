"""Shared raw Red/IR plot for the one-button demo."""
from collections import deque
from PySide6.QtCore import QPointF
from PySide6.QtGui import QPainter, QPen, QColor, QPolygonF
from PySide6.QtWidgets import QWidget

class Plot(QWidget):

    def __init__(self):
        super().__init__()
        self.rows = deque(maxlen=1000)
        self.window_samples=1000
        self.setMinimumSize(800, 430)
    def paintEvent(self, event):
        p = QPainter(self)
        p.fillRect(self.rect(), QColor('#15191f'))
        p.setRenderHint(QPainter.Antialiasing)
        w, h = self.width(), self.height()
        for col, name, color in [(1, 'RED raw ADC counts', '#ff7777'), (2, 'IR raw ADC counts', '#77caff')]:
            top = 30+(col-1)*(h//2)
            height = h//2-65
            rows = list(self.rows)
            values = [r[col] for r in rows]
            lo, hi = (min(values), max(values)) if values else (0, 1)
            pad = max(10, (hi-lo)*.1)
            lo, hi = max(0, lo-pad), hi+pad
            p.setPen(QColor('#eeeeee'))
            p.drawText(12, top-10, name + ' — autoscale')
            p.drawText(10, top+15, str(round(hi)))
            p.drawText(10, top+height, str(round(lo)))
            p.setPen(QColor('#667078'))
            p.drawRect(80, top, w-100, height)
            if len(rows)>1:
                p.setPen(QPen(QColor(color), 1.5))
                last = rows[-1][0]
                segment = []
                prev = None
                for r in rows:
                    if prev is not None and r[0]!=prev+1:
                        if len(segment)>1: p.drawPolyline(QPolygonF(segment))
                        segment=[]
                    span=self.window_samples-1
                    segment.append(QPointF(80+(r[0]-last+span)/span*(w-100),top+height-(r[col]-lo)/(hi-lo)*height))
                    prev=r[0]
                if len(segment)>1: p.drawPolyline(QPolygonF(segment))
            p.setPen(QColor('#eeeeee'))
            p.drawText(80, top+height+20, f'{self.window_samples} samples (~{self.window_samples/100:g} s at configured 100 samples/s)')
