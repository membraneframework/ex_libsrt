#include <srt/srt.h>

class Client {
public:
    Client() = default;
    ~Client() = default;

    void Initialize(const char *address, int port);

    void Connect();


};