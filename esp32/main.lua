
-- LuaTools需要PROJECT和VERSION这两个信息
PROJECT = "danmu_display"
VERSION = "1.0.0"

log.info("main", PROJECT, VERSION)

-- sys库是标配
_G.sys = require("sys")
_G.sysplus = require("sysplus")

-- UI带屏的项目一般不需要低功耗了吧, 设置到最高性能
if mcu then
    pm.request(pm.NONE)
end

--[[
-- LCD接法示例
LCD管脚       Air780E管脚    Air101/Air103管脚   Air105管脚
GND          GND            GND                 GND
VCC          3.3V           3.3V                3.3V
SCL          (GPIO11)       (PB02/SPI0_SCK)     (PC15/HSPI_SCK)
SDA          (GPIO9)        (PB05/SPI0_MOSI)    (PC13/HSPI_MOSI)
RES          (GPIO1)        (PB03/GPIO19)       (PC12/HSPI_MISO)
DC           (GPIO10)       (PB01/GPIO17)       (PE08)
CS           (GPIO8)        (PB04/GPIO20)       (PC14/HSPI_CS)
BL           (GPIO22)       (PB00/GPIO16)       (PE09)

提示:
1. 只使用SPI的时钟线(SCK)和数据输出线(MOSI), 其他均为GPIO脚
2. 数据输入(MISO)和片选(CS), 虽然是SPI, 但已复用为GPIO, 并非固定,是可以自由修改成其他脚
3. 若使用多个SPI设备, 那么RES/CS请选用非SPI功能脚
4. BL可以不接的, 若使用Air10x屏幕扩展板,对准排针插上即可
]]

local rtos_bsp = rtos.bsp()

-- spi_id,pin_reset,pin_dc,pin_cs,bl
function lcd_pin()
    if rtos_bsp == "AIR101" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR103" then
        return 0,pin.PB03,pin.PB01,pin.PB04,pin.PB00
    elseif rtos_bsp == "AIR105" then
        return 5,pin.PC12,pin.PE08,pin.PC14,pin.PE09
    elseif rtos_bsp == "ESP32C3" then
        return 2,10,6,7,11
    elseif rtos_bsp == "ESP32S3" then
        return 2,16,15,14,13
    elseif rtos_bsp == "EC618" then
        return 0,1,10,8,18
    else
        log.info("main", "bsp not support")
        return
    end
end

local spi_id,pin_reset,pin_dc,pin_cs,bl = lcd_pin()

-- v0006及以后版本可用pin方式, 请升级到最新固件 https://gitee.com/openLuat/LuatOS/releases
spi_lcd = spi.deviceSetup(spi_id,pin_cs,0,0,8,2000000,spi.MSB,1,0)

--[[ 此为合宙售卖的1.8寸TFT LCD LCD 分辨率:128X160 屏幕ic:st7735 购买地址:https://item.taobao.com/item.htm?spm=a1z10.5-c.w4002-24045920841.19.6c2275a1Pa8F9o&id=560176729178]]
-- direction：lcd屏幕方向 0:0° 1:180° 2:270° 3:90°
lcd.init("st7735s",{port = "device",pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 0,w = 128,h = 160,xoffset = 0,yoffset = 0},spi_lcd)

--如果显示颜色相反，请解开下面一行的注释，关闭反色
-- lcd.invoff()
--如果显示依旧不正常，可以尝试老版本的板子的驱动
--lcd.init("st7735s",{port = "device",pin_dc = pin_dc, pin_pwr = bl, pin_rst = pin_reset,direction = 2,w = 160,h = 80,xoffset = 0,yoffset = 0},spi_lcd)

-- 不在上述内置驱动的, 看demo/lcd_custom
local display_data = ''
local function devideutf8str_fromx(x, str) --在第x个utf8字符分割字符串成为两段，第一段有x个字符，第二段为剩下的字符
    local i = 0
    local s1 = ''
    local s2 = ''
    for c in string.gmatch(str, "[\0-\x7F\xC2-\xF4][\x80-\xBF]*") do
    i=i+1
    if i<x then
        s1 = s1 .. c
    else
        s2 = s2 .. c
    end
    end
    return s1,s2
end

queue = {} -- 创建一个空表
head = 1 -- 队列头的索引
tail = 0 -- 队列尾的索引
-- 入队操作
function enqueue (value)
    if tail - head + 1 >= 7 then -- 如果队列长度大于等于7
        dequeue() -- 从头部删除一个元素
    end
    tail = tail + 1 -- 尾部索引加一
    queue[tail] = value -- 在尾部插入值
end
-- 出队操作
function dequeue ()
    if head > tail then return '' end -- 如果队列为空，返回空字符串
    local value = queue[head] -- 取出头部的值
    queue[head] = nil -- 删除头部的值
    head = head + 1 -- 头部索引加一
    return value -- 返回出队的值
end

sys.taskInit(function() --存储弹幕消息
    local s1,s2
    for i = 1, 7 do -- 循环7次
        enqueue("") -- 入队一个空字符串
    end
    while true do
        local ret, _ = sys.waitUntil("mqtt_recv_data",30000)
        if ret then
            if utf8.len(display_data) < 12 then
            enqueue(display_data)
            else
                s1,s2 = devideutf8str_fromx(12, display_data)
                enqueue(s1)
                enqueue(s2)
            end
            sys.publish("new_danmu")
        end

    end
end)

sys.taskInit(function() --显示弹幕
    -- API 文档 https://wiki.luatos.com/api/lcd.html
    lcd.setFont(lcd.font_unifont_t_symbols)
    lcd.drawStr(65,10, "(@◠_◠)")
    lcd.setFont(lcd.font_opposansm10_chinese)
    lcd.drawStr(15,10,"弹幕姬", 0x1F405)
    local y = 30
    lcd.setFont(lcd.font_opposansm12_chinese)
    while true do --y30到150弹幕区，每隔20一行，一共7行可用
        sys.waitUntil("new_danmu",300000)
            lcd.fill(0,15,128,160,0xffff) -- 弹幕显示区域清屏
            for i = head, tail do
                lcd.drawStr(0, y, queue[i], 0x10ff)
                y = y + 20
            end
            y = 30
    end
end)


local mqttc = nil
local device_id     = "esp32"    --改为你自己的设备id
local device_secret = "132"    --改为你自己的设备密钥
local led_stat = 1
sys.taskInit(function()
--     -----------------------------
--     -- 统一联网函数, 可自行删减
--     ----------------------------
    if rtos.bsp():startsWith("ESP32") then
        -- wifi 联网, ESP32系列均支持
        local ssid = "耶耶"
        local password = "12345687!"
        -- log.info("wifi", ssid, password)
        -- TODO 改成esptouch配网
        wlan.init()
        wlan.setMode(wlan.STATION)
        wlan.connect(ssid, password, 1)
        local result, data = sys.waitUntil("IP_READY", 30000)
        log.info("wlan", "IP_READY", result, data)
        device_id = wlan.getMac()
    elseif rtos.bsp() == "AIR105" then
        -- w5500 以太网, 当前仅Air105支持
        w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
        w5500.config() --默认是DHCP模式
        w5500.bind(socket.ETH0)
        LED = gpio.setup(62, 0, gpio.PULLUP)
        sys.wait(1000)
        -- TODO 获取mac地址作为device_id
    elseif rtos.bsp() == "EC618" then
        -- Air780E/Air600E系列
        --mobile.simid(2)
        LED = gpio.setup(27, 0, gpio.PULLUP)
        device_id = mobile.imei()
        log.info("ipv6", mobile.ipv6(true))
        sys.waitUntil("IP_READY", 30000)
    end

    local client_id,user_name,password = iotauth.iotda(device_id,device_secret)
    log.info("iotda",client_id,user_name,password)
    mqttc = mqtt.create(nil,"192.168.1.103", 1883)
    mqttc:auth(client_id)
    mqttc:keepalive(30) -- 默认值240s
    mqttc:autoreconn(true, 3000) -- 自动重连机制

    mqttc:on(function(mqtt_client, event, data, payload)
        -- 用户自定义代码
        -- log.info("mqtt", "event:", event, mqtt_client, data, payload)
        if event == "conack" then
            sys.publish("mqtt_conack")
            mqtt_client:subscribe("msg/danmu")
        elseif event == "recv" then
            display_data = tostring(payload)
            log.info("接收到消息:", display_data, "strlen", utf8.len(display_data))
            sys.publish("mqtt_recv_data")

        elseif event == "sent" then

        end
    end)

    mqttc:connect()
	sys.waitUntil("mqtt_conack")
    led_stat = 2
    while true do
        -- mqttc自动处理重连
        local ret, topic, data, qos = sys.waitUntil("mqtt_pub", 30000)
        if ret then
            if topic == "close" then break end
            mqttc:publish(topic, data, qos)
        end
    end
    mqttc:close()
    mqttc = nil
end)

----------------------------
-- led_stat--1-双灯闪烁初始化；2--mqtt服务已连接,接收到消息后闪烁；
-----------------------------
sys.taskInit(function()
    while true do
        if led_stat == 1 then
            gpio.setup(12,gpio.HIGH)
            gpio.setup(13,gpio.HIGH)
            sys.wait(50)
            gpio.setup(12,gpio.LOW)
            gpio.setup(13,gpio.LOW)
            sys.wait(50)
        elseif led_stat == 2 then
            gpio.setup(12,gpio.LOW)
            gpio.setup(13,gpio.LOW)
            local ret, _ = sys.waitUntil("mqtt_recv_data",30000)
            if ret then
                gpio.setup(12,gpio.HIGH)
                gpio.setup(13,gpio.HIGH)
                sys.wait(50)
                gpio.setup(12,gpio.LOW)
                gpio.setup(13,gpio.LOW)
                sys.wait(50)
            end
        end
    end
end)

-- local wsc = nil
-- local roomid = 4716116
-- local function encode(bililiveroomid)

-- end
-- local function decode(datafromwebserver)

-- end

-- sys.taskInit(function()
--     -----------------------------
--     -- 统一联网函数, 可自行删减
--     ----------------------------
--     if rtos.bsp():startsWith("ESP32") then
--         -- wifi 联网, ESP32系列均支持
--         local ssid = "耶耶"
--         local password = "12345687!"
--         -- log.info("wifi", ssid, password)
--         -- TODO 改成esptouch配网
--         wlan.init()
--         wlan.setMode(wlan.STATION)
--         wlan.connect(ssid, password, 1)
--         local result, data = sys.waitUntil("IP_READY", 30000)
--         log.info("wlan", "IP_READY", result, data)
--         device_id = wlan.getMac()
--     elseif rtos.bsp() == "AIR105" then
--         -- w5500 以太网, 当前仅Air105支持
--         w5500.init(spi.HSPI_0, 24000000, pin.PC14, pin.PC01, pin.PC00)
--         w5500.config() --默认是DHCP模式
--         w5500.bind(socket.ETH0)
--         LED = gpio.setup(62, 0, gpio.PULLUP)
--         sys.wait(1000)
--         -- TODO 获取mac地址作为device_id
--     elseif rtos.bsp() == "EC618" then
--         -- Air780E/Air600E系列
--         --mobile.simid(2)
--         LED = gpio.setup(27, 0, gpio.PULLUP)
--         device_id = mobile.imei()
--         log.info("ipv6", mobile.ipv6(true))
--         sys.waitUntil("IP_READY", 30000)
--     end

--     wsc = websocket.create(nil,'ws://broadcastlv.chat.bilibili.com:2244/sub')
--     -- wsc:autoreconn(true, 3000) -- 自动重连机制
--     wsc:on(function(wsc, event, data, fin, optcode)
--         -- event 事件, 当前有conack和recv
--         -- data 当事件为recv是有接收到的数据
--         -- fin 是否为最后一个数据包, 0代表还有数据, 1代表是最后一个数据包
--         -- optcode, 0 - 中间数据包, 1 - 文本数据包, 2 - 二进制数据包
--         -- 因为lua并不区分文本和二进制数据, 所以optcode通常可以无视
--         -- 若数据不多, 小于1400字节, 那么fid通常也是1, 同样可以忽略
--         log.info("wsc", event, data, fin, optcode)
--         if event == "conack" then -- 连接websocket服务后, 会有这个事件
--             -- wsc:send(encode(roomid))
--             wsc:send('\x00\x00\x00"\x00\x10\x00\x01\x00\x00\x00\x07\x00\x00\x00\x01{"roomid":4716116}') --进房间
--             sys.publish("wsc_conack")
--         end
--         if event == "recv" then
--             -- decode(data)
--             log.info("收到的数据", type(data), data)
--         end
--     end)
--     wsc:connect()
--     while true do
--         sys.wait(30000) --30s发一次心跳包
--         wsc:send('\x00\x00\x00\x10\x00\x10\x00\x01\x00\x00\x00\x02\x00\x00\x00\x01')
--         log.info("HeartBeat Package Send.")
--     end
--     wsc:close()
--     wsc = nil
-- end)


-- 用户代码已结束---------------------------------------------
-- 结尾总是这一句
sys.run()
-- sys.run()之后后面不要加任何语句!!!!!
