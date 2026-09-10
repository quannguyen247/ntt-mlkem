"""Conservative demo estimator, NOT a medical or calibrated oximeter.
Theory/empirical polynomial: ADI KA-06685 and Guidelines for SpO2 Measurement.
Thresholds below are engineering heuristics, not validated finger detection.
"""
import math, statistics as st, json, csv, sys
from pathlib import Path

def correlation(a,b):
    ma,mb=st.mean(a),st.mean(b)
    aa=[x-ma for x in a];bb=[x-mb for x in b]
    den=math.sqrt(sum(x*x for x in aa)*sum(x*x for x in bb))
    return sum(x*y for x,y in zip(aa,bb))/den if den else 0

def detrend(a):
    # Remove linear drift, then smooth over 5 samples at configured 100 Hz.
    n=len(a);mx=(n-1)/2;my=st.mean(a)
    slope=sum((i-mx)*(v-my) for i,v in enumerate(a))/sum((i-mx)**2 for i in range(n))
    d=[v-my-slope*(i-mx) for i,v in enumerate(a)]
    return [st.mean(d[i-2:i+3]) for i in range(2,n-2)]

def estimate(rows,fs=100):
    r={'accepted':False,'bpm':None,'spo2':None,'reason':'Chưa đủ tín hiệu',
       'calibrated':False,'medical_use':False,'sample_rate_hz':fs}
    def reject(msg):r['reason']=msg;return r
    if len(rows)<1000:return reject('Cần khoảng 10 giây mẫu liên tục')
    if any(rows[i][0]!=rows[i-1][0]+1 for i in range(1,len(rows))):return reject('Mất mẫu')
    if any(not 0<=x<262144 for row in rows for x in row[1:]):return reject('Raw ngoài miền 18-bit')
    rows=rows[200:] # Ignore initial settling, but no invented/replaced samples.
    red=[x[1] for x in rows];ir=[x[2] for x in rows]
    dc=[st.mean(red),st.mean(ir)]
    r['dc_red'],r['dc_ir']=dc
    # The breakout's absolute count depends on LED current and optical geometry.
    # This module can produce usable PPG in the low-thousands, so use
    # pulsatility and periodicity below instead of a fixed 5000-count gate.
    if min(dc)<200:return reject('Mức phản xạ quá thấp: chưa có tay hoặc tín hiệu quá yếu')
    if max(red+ir)>=260000:return reject('Tín hiệu gần bão hòa')
    for a,m in zip((red,ir),dc):
        chunks=[st.mean(a[i:i+100]) for i in range(0,len(a)-99,100)]
        if (max(chunks)-min(chunks))/m>.08:return reject('Tay/ánh sáng thay đổi quá nhiều; giữ yên rồi thử lại')
    a,b=detrend(red),detrend(ir)
    ac=[math.sqrt(st.mean(x*x for x in v)) for v in (a,b)]
    pi=[ac[i]/dc[i] for i in (0,1)]
    r['perfusion_rms']=pi
    if min(pi)<.0003 or max(pi)>.5:return reject('Biên độ dao động chưa đủ tin cậy')
    corr=correlation(a,b);r['red_ir_correlation']=corr
    if corr<.85:return reject('Hai kênh Red/IR chưa đồng nhất')
    lags=range(33,151)
    scores={lag:correlation(b[:-lag],b[lag:]) for lag in lags}
    peaks=[lag for lag in range(34,150) if scores[lag]>=scores[lag-1] and scores[lag]>scores[lag+1]]
    if not peaks:return reject('Chưa thấy chu kỳ nhịp rõ')
    best=max(scores[k] for k in peaks)
    if best<.65:return reject('Chu kỳ chưa ổn định')
    # `best` is allowed down to 0.65, so requiring 0.8 here can leave the
    # generator empty even after the signal passed the previous check.  Pick
    # the shortest peak within 95% of the best score; `best` itself always
    # satisfies this threshold, so this path cannot crash on weak input.
    near_best=[k for k in peaks if scores[k]>=best*.95]
    lag=min(near_best)
    # Require both halves to support the same period, not just a single transient.
    for half in (b[:len(b)//2],b[len(b)//2:]):
        if correlation(half[:-lag],half[lag:])<.55:return reject('Nhịp không ổn định trong cả cửa sổ')
    ratio=pi[0]/pi[1]
    spo2=-45.060*ratio*ratio+30.354*ratio+94.845
    # No clamping into a plausible-looking clinical range.
    if not 70<=spo2<=100:return reject('Ước lượng ngoài miền demo; cần tín hiệu/hiệu chuẩn tốt hơn')
    r.update(accepted=True,bpm=round(60*fs/lag,1),spo2=round(spo2,1),ratio=ratio,
             autocorrelation=scores[lag],reason='Đạt kiểm tra tín hiệu demo; số ước lượng chưa hiệu chuẩn')
    return r

if __name__=='__main__':
    p=Path(sys.argv[1])
    with (p/'quality_raw.csv').open() as f:rows=[(int(r['index']),int(r['red']),int(r['ir'])) for r in csv.DictReader(f)]
    result=estimate(rows)
    (p/'quality.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(result['reason']);sys.exit(0 if result['accepted'] else 2)
