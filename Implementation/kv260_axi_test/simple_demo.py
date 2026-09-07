"""One-button, quality-gated PPG estimate -> NTT -> INTT demonstration."""
import sys,json,csv
from pathlib import Path
from PySide6.QtCore import QProcess,QTimer
from PySide6.QtWidgets import QApplication,QWidget,QVBoxLayout,QLabel,QPushButton
from raw_plot import Plot
HERE=Path(__file__).resolve().parent
class Demo(QWidget):
    def __init__(self):
        super().__init__();self.setWindowTitle('KV260 — RAW → NTT → INTT');self.resize(1050,720)
        l=QVBoxLayout(self)
        l.addWidget(QLabel('Đặt nhẹ ngón tay, giữ yên rồi bấm Chạy demo. Thu khoảng 10 giây; tín hiệu chưa đạt sẽ KHÔNG chạy NTT/INTT.'))
        self.vitals=QLabel('BPM: — | SpO₂: — / Chưa đủ tín hiệu');l.addWidget(self.vitals)
        self.status=QLabel('Sẵn sàng — chưa chạy');self.status.setWordWrap(True);l.addWidget(self.status)
        self.result=QLabel('RAW: CHƯA TEST | NTT: CHƯA TEST | INTT: CHƯA TEST');l.addWidget(self.result)
        self.button=QPushButton('Chạy demo: đọc raw → kiểm tra NTT + INTT');l.addWidget(self.button)
        self.button.clicked.connect(self.run)
        self.plot=Plot();self.plot.rows=__import__('collections').deque(maxlen=1024);self.plot.window_samples=1024;l.addWidget(self.plot)
        l.addWidget(QLabel('BPM/SpO₂ là ƯỚC LƯỢNG DEMO, CHƯA HIỆU CHUẨN — không dùng đánh giá sức khỏe. Đồ thị là đợt vừa thu.'))
        self.process=QProcess(self);self.process.setProcessChannelMode(QProcess.MergedChannels)
        self.process.setWorkingDirectory(str(HERE));self.process.readyReadStandardOutput.connect(self.read)
        self.process.finished.connect(self.done);self.process.errorOccurred.connect(self.error)
        self.buffer='';self.evidence=None
    def run(self):
        self.button.setEnabled(False);self.buffer='';self.evidence=None
        self.result.setText('RAW: ĐANG ĐỌC | NTT/INTT: ĐANG CHỜ');self.result.setStyleSheet('')
        self.vitals.setText('BPM: — | SpO₂: — / Đang thu mẫu mới')
        self.plot.rows.clear();self.plot.update()
        self.status.setText('Đang chạy thật trên kit, chờ khoảng 15–30 giây. Không chạy app live khác cùng lúc.')
        self.process.start(sys.executable,['-u',str(HERE/'verify_sensor_ntt.py'),'--quality-gate'])
    def read(self):
        text=bytes(self.process.readAllStandardOutput()).decode(errors='replace');self.buffer+=text
        print(text,end='',flush=True)
        for line in text.splitlines():
            if line.startswith('EVIDENCE='):self.evidence=Path(line.split('=',1)[1])
    def error(self,e):self.status.setText('Lỗi chạy: '+self.process.errorString());self.button.setEnabled(True)
    def done(self,code,state):
        self.read();self.button.setEnabled(True)
        # Parse complete accumulated output, including split process chunks.
        for line in self.buffer.splitlines():
            if line.startswith('EVIDENCE='):self.evidence=Path(line.split('=',1)[1])
        if self.evidence is None or not (self.evidence/'result.json').exists():
            self.result.setText('TEST KHÔNG HOÀN TẤT — chưa kết luận NTT/INTT sai')
            self.vitals.setText('BPM: — | SpO₂: — / Lỗi thu hoặc kiểm thử')
            self.status.setText(self.buffer[-1000:]);return
        r=json.loads((self.evidence/'result.json').read_text())
        q=r.get('quality') or {}
        if r['status']=='INSUFFICIENT_SIGNAL':
            self.result.setText('NTT: CHƯA CHẠY | INTT: CHƯA CHẠY')
            self.vitals.setText('BPM: — | SpO₂: — / Chưa đủ tín hiệu')
        else:
            self.result.setText(f"NTT: {r['ntt_status']} (1024 hệ số) | INTT: {r['intt_status']} (1024 hệ số)")
            self.vitals.setText(f"Ước lượng demo: BPM ≈ {q.get('bpm','—')} | SpO₂ ≈ {q.get('spo2','—')}% — chưa hiệu chuẩn")
        self.result.setStyleSheet('font-weight:bold;color:'+('#5edc91' if code==0 and r['status']=='PASS' else '#ff7777'))
        self.status.setText(q.get('reason','')+' | Kết quả đợt vừa thu. Bằng chứng: '+str(self.evidence))
        rawpath=self.evidence/'quality_raw.csv'
        if not rawpath.exists():rawpath=self.evidence/'sensor_raw.csv'
        with rawpath.open() as f:
            rows=[(int(r['index']),int(r['red']),int(r['ir'])) for r in csv.DictReader(f)]
        self.plot.rows.clear();self.plot.rows.extend(rows);self.plot.update()
        self.grab().save(str(HERE/'output/simple_demo_preview.png'))
    def closeEvent(self,e):
        if self.process.state()!=QProcess.NotRunning:
            self.status.setText('Đợi lượt kiểm thử kết thúc trước khi đóng.');e.ignore()
        else:e.accept()
if __name__=='__main__':
    app=QApplication(sys.argv);w=Demo();w.show()
    if '--run' in sys.argv:QTimer.singleShot(300,w.run)
    sys.exit(app.exec())
