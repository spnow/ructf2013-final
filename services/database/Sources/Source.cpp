﻿#include "libjson/libjson.h"
#include "HttpServer.h"
#include "Errors.h"
#include "Parser.h"
#include "Query.h"

using namespace std;

const string port = "16744";
const string dbpath = "bases";
const string authurl = "http://dqteam.org/public/auth/index.html";

int main()
{
	Storage::Initialize();
	Storage::SetDbPath(dbpath);

	Database *syntaxDb = Storage::FindDatabase(".syntax");
	Parser::Initialize(*syntaxDb->GetJson());

	cout << "Hello and welcome to the Database service." << endl;
	HttpServer server;
	server.SetAuthUrl(authurl);
	server.SetHandler([] (const string &msg, const string &id) {		
		cout << "Have a request!" << endl;
		JSONNode data = libjson::parse(msg);
		Query *query = Parser::Parse(data.find("query")->as_string(), id);
		if (query == NULL)
			return errorStrings[ERR_SYNTAX];
		JSONNode *result;
		int errcode = query->Execute(result);
		if (errcode != ERR_OK)
			return errorStrings[errcode];
		result->set_name("data");
		JSONNode n;
		n.push_back(JSONNode("status", "OK"));
		n.push_back(*result);
		delete result;
		return n.write_formatted();
	});
	server.Listen(port);

	Storage::Flush();

	return 0;
}
