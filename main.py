# -*- coding: utf-8 -*-

#python弹幕姬,更改roomid（房间号）即可监测直播间弹幕及其他信息
import asyncio
import zlib
from aiowebsocket.converses import AioWebSocket
import json
import os

remote = 'ws://broadcastlv.chat.bilibili.com:2244/sub'
roomid = input("请输入房间号:")
if(len(roomid)==0):
    roomid = '4716116'
# roomid = '4716116'

data_raw = '000000{headerLen}0010000100000007000000017b22726f6f6d6964223a{roomid}7d'
data_raw = data_raw.format(headerLen=hex(27 + len(roomid))[2:], roomid=''.join(map(lambda x: hex(ord(x))[2:], list(roomid))))

async def startup():
    async with AioWebSocket(remote) as aws:
        converse = aws.manipulator
        await converse.send(bytes.fromhex(data_raw))
        # print("发送",bytes.fromhex(data_raw))
        tasks = [receDM(converse), sendHeartBeat(converse)]
        await asyncio.wait(tasks)
hb='00 00 00 10 00 10 00 01 00 00 00 02 00 00 00 01'
async def sendHeartBeat(websocket):
    while True:
        await asyncio.sleep(30)
        await websocket.send(bytes.fromhex(hb))
        # print(bytes.fromhex(hb))
        print('[Notice] Sent HeartBeat.')
async def receDM(websocket):
    while True:
        recv_text = await websocket.receive()
        if recv_text == None:
            recv_text = b'\x00\x00\x00\x1a\x00\x10\x00\x01\x00\x00\x00\x08\x00\x00\x00\x01{"code":0}'
        # print(recv_text)
        printDM(recv_text)


# 将数据包传入：
def printDM(data):
    # 获取数据包的长度，版本和操作码
    packetLen = int(data[:4].hex(), 16)
    ver = int(data[6:8].hex(), 16)
    op = int(data[8:12].hex(), 16)


    # 有的时候可能会两个数据包连在一起发过来，所以利用前面的数据包长度判断，
    if (len(data) > packetLen):
        printDM(data[packetLen:])
        data = data[:packetLen]

    # 有时会发送过来 zlib 压缩的数据包，这个时候要去解压。
    if (ver == 2):
        data = zlib.decompress(data[16:])
        printDM(data)
        return

    # ver 为1的时候为进入房间后或心跳包服务器的回应。op 为3的时候为房间的人气值。
    if (ver == 1):
        if (op == 3):
            print('[人气]  {}'.format(int(data[16:].hex(), 16)))
        return


    # ver 不为2也不为1目前就只能是0了，也就是普通的 json 数据。
    # op 为5意味着这是通知消息，cmd 基本就那几个了。
    if (op == 5):
        try:

            jd = json.loads(data[16:].decode('utf-8', errors='ignore'))
            if (jd['cmd'] == 'DANMU_MSG'):
                print('[弹幕] ', jd['info'][2][1], ': ', jd['info'][1])
                msg = '[id]' + jd['info'][2][1] + ': ' + jd['info'][1]
                os.system(f'mosquitto_pub -h 192.168.1.103 -p 1883 -t \'msg/danmu\' -m "{msg}"')
            elif (jd['cmd'] == 'SEND_GIFT'):
                print('[礼物]', jd['data']['uname'], ' ', jd['data']['action'], ' ', jd['data']['num'], 'x', jd['data']['giftName'])
                msg = str(jd['data']['uname'])+ ' ' + str(jd['data']['action'])+ ' ' + str(jd['data']['num'])+ ' x ' + str(jd['data']['giftName'])
                os.system(f'mosquitto_pub -h 192.168.1.103 -p 1883 -t \'msg/danmu\' -m "{msg}"')
            elif (jd['cmd'] == 'LIVE'):
                print('[Notice] LIVE Start!')
            elif (jd['cmd'] == 'PREPARING'):
                print('[Notice] LIVE Ended!')
            elif (jd['cmd'] == 'INTERACT_WORD'): #谁进入直播间
                print(jd['data']['uname'], " 进入直播间")
                msg ="[new]" + jd['data']['uname']+ " 进入直播间"
                os.system(f'mosquitto_pub -h 192.168.1.103 -p 1883 -t \'msg/danmu\' -m "{msg}"')

                # with open("message.json", "w", encoding='utf-8') as file:
                #     s = data[16:].decode('utf-8', errors='ignore')
                #     file.write(json.dumps(s, ensure_ascii=False , indent=4 , separators=(',', ':')))
            # else:
            #     print('[其他字段] ', jd['cmd'])



            # print(json.dumps(data[16:].decode('utf-8', errors='ignore'),ensure_ascii=False, indent=4))
        except Exception as e:
            pass



if __name__ == '__main__':
    try:
        loop = asyncio.get_event_loop()
        loop.run_until_complete(startup())
    except Exception as e:
        print('退出')

