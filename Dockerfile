FROM outdoorsafetylab/demd:1.2.2

RUN mkdir -p /var/lib/dem/
COPY /台灣本島及4離島(龜山島_綠島_蘭嶼_小琉球)/*.tif /var/lib/dem/
COPY /*.tif /var/lib/dem/
