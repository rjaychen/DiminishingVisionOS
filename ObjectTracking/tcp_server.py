import socket
import numpy as np
#import time 
import struct
import cv2
from mss import mss
from PIL import Image



def send_array(sock, array):
    # Convert the NumPy array to bytes
    data = array.tobytes()
    # Send the length of the data
    sock.sendall(struct.pack(">I", len(data)))
    # Send the actual data
    sock.sendall(data)

def start_server(host, port):
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.bind((host, port))
    server_socket.listen(1)
    print(f"Listening on {host}:{port}...")


    while True:
        client_socket, addr = server_socket.accept()
        print(f"Accepted connection from {addr}")

        try:
            bounding_box = {'top': 0, 'left': 0, 'width': 1920, 'height': 1080} # set screen dimensions
            sct = mss()
            while True:
                # # Generate a random NumPy array to send
                # array = np.random.rand(100, 100).astype(np.float32)
                # print(f"Sending array of shape {array.shape}")

                sct_img = sct.grab(bounding_box)
                array = cv2.cvtColor(np.asarray(sct_img), cv2.COLOR_BGR2RGB) # this step removes the alpha channel
                array = cv2.resize(array, dsize=(1920,1080)) # [:,:,:3] // if removing alpha c
                
                # cv2.imwrite('img.png', array)
                print(f"Sending array of shape {array.shape}")
                # Send the array to the client
                send_array(client_socket, array)
                k = cv2.waitKey(1) & 0xFF
                if k == 27:
                    cv2.destroyAllWindows()
                    client_socket.close()
                    break

        except BrokenPipeError:
            print("Client disconnected")
        finally:
            client_socket.close()

if __name__ == "__main__":
    start_server("10.197.8.244", 8000)
