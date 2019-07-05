package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"net/http/httputil"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"time"
)

func handler(w http.ResponseWriter, r *http.Request) {
	log.Print("Request for URI: ", r.URL.Path)
	log.Print("Method: ", r.Method)
	//for key, value := range r.Header {
	//	log.Print("Header: ", key, " = ", value)
	//}
	dump, _ := httputil.DumpRequest(r, true)
	log.Printf("%q", dump)

	message := "Hello!"
	if len(os.Getenv("MESSAGE")) > 0 {
		message = os.Getenv("MESSAGE")
	}

	w.Header().Set("Content-Type", "text/plain")
	fmt.Fprintf(w, "%s: %s\n", os.Getenv("HOSTNAME"), message)
}

func main() {
	var port int

	flag.IntVar(&port, "port", 8080, "HTTP listener port")
	flag.Parse()

	env := getPortEnv()
	if env > 0 {
		port = env
	}

	// Setup signal handling.
	shutdown := make(chan os.Signal)
	signal.Notify(shutdown, os.Interrupt)

	var wg sync.WaitGroup
	server := &http.Server{
		Addr:    fmt.Sprintf(":%d", port),
		Handler: http.HandlerFunc(handler),
	}
	go func() {
		log.Printf("listening on port %v", port)
		http.HandleFunc("/", handler)
		wg.Add(1)
		defer wg.Done()
		if err := server.ListenAndServe(); err != nil {
			if err == http.ErrServerClosed {
				log.Print("web server graceful shutdown")
				return
			}
			log.Fatal(err)
		}
	}()

	// Wait for SIGINT
	<-shutdown
	log.Print("interrupt signal received, initiating web server shutdown...")
	signal.Reset(os.Interrupt)

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	server.Shutdown(ctx)

	wg.Wait()
	log.Print("Shutdown successful")
}

func getPortEnv() int {
	s := os.Getenv("PORT")
	if len(s) == 0 {
		return 0
	}
	i, err := strconv.Atoi(s)
	if err != nil {
		return 0
	}
	return i
}
