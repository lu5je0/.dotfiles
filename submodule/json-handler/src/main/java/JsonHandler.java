import com.alibaba.fastjson.JSONObject;
import com.alibaba.fastjson.serializer.SerializerFeature;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStreamReader;

public class JsonHandler {

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));

        StringBuilder builder = new StringBuilder();
        while (true) {
            String line = reader.readLine();
            if (line == null) {
                break;
            }
            builder.append(line);
        }
        JSONObject jsonObject = JSONObject.parseObject(builder.toString());

        System.out.println(jsonObject.toString(SerializerFeature.WriteNonStringKeyAsString));
    }

}
