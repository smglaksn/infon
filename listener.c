/*
   
    Copyright (c) 2006 Florian Wesch <fw@dividuum.de>. All Rights Reserved.
    
    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.
    
    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    59 Temple Place - Suite 330, Boston, MA  02111-1307, USA

*/

#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>

#include <event.h>

#include "infond.h"
#include "global.h"
#include "server.h"
#include "listener.h"
#include "server.h"

static int listenfd = -1;
static struct event listener_event;

static void listener_cb(int fd, short event, void *arg) {
    struct sockaddr_in peer;
    socklen_t addrlen = sizeof(struct sockaddr_in);
        
    int clientfd;
    
    /* Neue Verbindung accept()ieren */
    clientfd = accept(listenfd, (struct sockaddr*)&peer, &addrlen);

    if (clientfd == -1) {
        /* Warning nur anzeigen, falls accept() fehlgeschlagen hat allerdings
           ohne dabei EAGAIN (was bei non-blocking sockets auftreten kann)
           zu melden. */
        if (errno != EAGAIN) 
            fprintf(stderr, "cannot accept() new incoming connection: %s\n", strerror(errno));

        goto error;
    }

    /* TCP_NODELAY setzen. Dadurch werden Daten fruehestmoeglich versendet */
    static const int one = 1;
    if (setsockopt(clientfd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one)) < 0) {
        fprintf(stderr, "cannot enable TCP_NODELAY: %s\n", strerror(errno));
        goto error;
    }

    /* SO_LINGER setzen. Falls sich noch Daten in der Sendqueue der Verbindung
       befinden, werden diese verworfen. */
    static const struct linger l = { 1, 0 };
    if (setsockopt(clientfd, SOL_SOCKET, SO_LINGER, &l, sizeof(l)) == -1) {
        fprintf(stderr, "cannot set SO_LINGER: %s\n", strerror(errno));
        goto error;
    }

    static char address[128];
    sprintf(address, "ip:%s:%d", inet_ntoa(peer.sin_addr), ntohs(peer.sin_port));

    if (!server_accept(clientfd, address))
        goto error; 

    return;
error:
    if (clientfd != -1)
        close(clientfd);
}

void listener_shutdown() {
    if (listenfd == -1) 
        return;

    event_del(&listener_event);
    close(listenfd);
    listenfd = -1;
}

int listener_init(const char *listenaddr, int port) {
    struct sockaddr_in addr;
    static const int one = 1;

    /* Alten Listener, falls vorhanden, schliessen */
    listener_shutdown();

    /* Keinen neuen starten? */
    if (strlen(listenaddr) == 0)
        return 1;

    /* Adressstruktur f�llen */
    memset(&addr, 0, sizeof(struct sockaddr_in));
    addr.sin_family        = AF_INET;
    addr.sin_addr.s_addr   = inet_addr(listenaddr);
    addr.sin_port          = htons(port);

    /* Socket erzeugen */
    listenfd = socket(AF_INET, SOCK_STREAM, 0);

    /* Fehler beim Socket erzeugen? */
    if (listenfd == -1) {
        fprintf(stderr, "cannot open socket: %s\n", strerror(errno));
        goto error;
    }

    /* Auf nonblocking setzen */
    if (fcntl(listenfd, F_SETFL, O_NONBLOCK) == -1) {
        fprintf(stderr, "cannot set socket nonblocking: %s\n", strerror(errno));
        goto error;
    }

    /* SO_REUSEADDR verwenden. Falls sich zuvor ein Programm unsch�n
       beendet hat, so ist der port normalerweise f�r einen bestimmten
       Zeitrahmen weiterhin belegt. SO_REUSEADDR verwendet dann den
       belegten Port weiter. */
    if (setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one)) == -1) {
        fprintf(stderr, "cannot enable SO_REUSEADDR: %s\n", strerror(errno));
        goto error;
    }

    /* Socket bind()en */
    if (bind(listenfd, (struct sockaddr *)&addr, sizeof(struct sockaddr_in)) == -1) {
        fprintf(stderr, "cannot bind socket: %s\n", strerror(errno));
        goto error;
    }

    /* Und listen() mit einem backlog von 128 Verbindungen. Wobei
       dies eventuell ignoriert wird, falls SYN cookies aktiviert sind */
    if (listen(listenfd, 128) == -1) {
        fprintf(stderr, "cannot listen() on socket: %s\n", strerror(errno));
        goto error;
    }

    event_set(&listener_event, listenfd, EV_READ | EV_PERSIST, listener_cb, &listener_event);
    event_add(&listener_event, NULL);

    return 1;
error:
    if (listenfd != -1) {
        close(listenfd);
        listenfd = -1;
    }
    return 0;
}
