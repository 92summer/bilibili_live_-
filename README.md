# bilibili_live_-
包含python实现的和esp32驱动lcd屏幕实现的  
  
**python参考**

[API](https://github.com/lovelyyoshino/Bilibili-Live-API/blob/master/API.WebSocket.md)

[思路](https://blog.csdn.net/Sharp486/article/details/122466308)  

**esp32c3实现**  
由于luatos的websocket库接收到的数据始终显示不出来，所以采用本地mqtt传输的方法将弹幕显示在tftlcd上  
[硬件参数](https://github.com/92summer/esp32_LuatOS)

